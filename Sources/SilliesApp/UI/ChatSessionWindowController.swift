import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

enum ChatWindowLayout {
  static let talkSize = CGSize(width: 360, height: 340)
  static let initialSize = CGSize(width: 400, height: 560)
  static let minimumSize = CGSize(width: 360, height: 440)
}

@MainActor final class ChatSessionWindowController: NSObject, NSWindowDelegate {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
    super.init()
  }

  private static let animationDuration: TimeInterval = 0.18
  private static let entranceOffset: CGFloat = 14
  private var animationID = UUID()
  private(set) var window: CompanionUtilityWindow?
  private let bubble = ConversationBubblePresentation()
  private var anchor: ConversationCompanionAnchor?
  private weak var displayedSession: ChatSession?
  let dismissal = ConversationWindowDismissal()
  var prefersReducedMotion: () -> Bool = { false }
  private var reducesMotion: Bool {
    prefersReducedMotion() || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func show(
    _ model: ChatSession, openSettings: @escaping (ChatNotice.SettingsDestination) -> Void,
    renderer: String? = nil, vault: ChatVaultPresentation? = nil,
    anchor: ConversationCompanionAnchor? = nil
  ) {
    prepare(model, openSettings: openSettings, renderer: renderer, vault: vault, anchor: anchor)
    reveal()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Builds the native bubble without activation; presentation is owned by `show`.
  func prepare(
    _ model: ChatSession, openSettings: @escaping (ChatNotice.SettingsDestination) -> Void,
    renderer: String? = nil, vault: ChatVaultPresentation? = nil,
    anchor: ConversationCompanionAnchor? = nil
  ) {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: ChatWindowLayout.initialSize),
        styleMask: [.borderless], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentMinSize = ChatWindowLayout.minimumSize
      window.delegate = self
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true
      window.isMovable = false
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.level = .normal
      AppContentWindowStacking.shared.register(window)
      appearance.register(window, background: .transparent)
      window.center()
      self.window = window
    }
    if let anchor { attach(to: anchor) }
    window?.title = String(localized: "Sillies · Chat with \(model.companionName)")
    if displayedSession !== model {
      dismissal.stop()
      let view = ThemedHostingView(
        rootView: ConversationBubbleView(
          presentation: bubble,
          content: ChatSessionView(
            model: model, openSettings: openSettings, renderer: renderer,
            motion: reducesMotion ? .reduced : .animated, vault: vault)), appearance: appearance)
      view.sizingOptions = []
      window?.contentView = view
      displayedSession = model
      observeMode(model)
    }
  }
  func follow(_ anchor: ConversationCompanionAnchor) {
    guard displayedSession?.companionID == anchor.companionID else { return }
    attach(to: anchor)
  }
  private func attach(to anchor: ConversationCompanionAnchor) {
    self.anchor = anchor
    guard let window else { return }
    AppContentWindowStacking.shared.setBackgroundLevel(
      CompanionPanel.hudLevel(forWindowLayer: anchor.windowLayer), for: window)
    let minimumSize = windowSize(
      displayedSession?.mode == .talk ? ChatWindowLayout.talkSize : ChatWindowLayout.minimumSize,
      edge: anchor.edge)
    if window.contentMinSize != minimumSize { window.contentMinSize = minimumSize }
    let layout = ConversationBubbleLayout(
      anchor: anchor.position,
      size: windowSize(
        displayedSession?.mode == .talk
          ? ChatWindowLayout.talkSize : ChatWindowLayout.initialSize, edge: anchor.edge),
      visibleFrame: anchor.visibleFrame, edge: anchor.edge)
    if bubble.tail != layout.tail { bubble.tail = layout.tail }
    if bubble.tailOffset != layout.tailOffset { bubble.tailOffset = layout.tailOffset }
    // AppKit rounds native window origins; avoid resubmitting the same sub-point movement.
    let frame = CGRect(
      origin: CGPoint(x: layout.frame.minX.rounded(), y: layout.frame.minY.rounded()),
      size: layout.frame.size)
    if window.frame.size != frame.size {
      window.setFrame(frame, display: false)
    } else if window.frame.origin != frame.origin {
      window.setFrameOrigin(frame.origin)
    }
  }
  private func windowSize(_ verticalSize: CGSize, edge: PerchSurface.Edge) -> CGSize {
    ConversationBubbleLayout.windowSize(
      forBody: CGSize(
        width: verticalSize.width,
        height: verticalSize.height - ConversationBubbleLayout.tailHeight), edge: edge)
  }
  private func observeMode(_ model: ChatSession) {
    if let anchor { attach(to: anchor) }
    updateDismissal()
    withObservationTracking {
      _ = model.mode
    } onChange: { [weak self, weak model] in
      MainRunLoopDelivery.perform {
        guard let self, let model, self.displayedSession === model else { return }
        self.observeMode(model)
      }
    }
  }
  private func reveal() {
    guard let window else { return }
    animationID = UUID()
    let target = window.frame
    let animate = !window.isVisible && !reducesMotion
    if animate {
      window.alphaValue = 0
      window.setFrame(target.offsetBy(dx: 0, dy: -Self.entranceOffset), display: false)
    }
    window.makeKeyAndOrderFront(nil)
    updateDismissal()
    window.contentView?.layoutSubtreeIfNeeded()
    if let editor = composer(in: window.contentView) { window.makeFirstResponder(editor) }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animate ? Self.animationDuration : 0
      window.animator().alphaValue = 1
      window.animator().setFrame(target, display: false)
    }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    dismissConversation()
    return false
  }
  func dismissConversation() {
    dismissal.stop()
    displayedSession?.onFinish?()
    if window != nil { close() }
  }
  private func updateDismissal() {
    guard let window, window.isVisible, displayedSession?.mode == .chat else {
      dismissal.stop()
      return
    }
    if !dismissal.isMonitoring {
      dismissal.start(window: window) { [weak self] in
        guard self?.displayedSession?.mode == .chat else { return }
        self?.dismissConversation()
      }
    }
  }
  func windowWillClose(_ notification: Notification) {
    dismissal.stop()
    displayedSession?.stopVoiceConversation()
  }
  private func composer(in view: NSView?) -> ChatComposerTextView? {
    if let composer = view as? ChatComposerTextView { return composer }
    for child in view?.subviews ?? [] {
      if let found = composer(in: child) { return found }
    }
    return nil
  }
  func close(_ session: ChatSession) {
    if displayedSession === session { close() }
  }
  func close() {
    dismissal.stop()
    animationID = UUID()
    guard let closing = window else { return }
    window = nil
    displayedSession = nil
    anchor = nil
    closing.delegate = nil
    closing.ignoresMouseEvents = true
    guard closing.isVisible, !reducesMotion else {
      closing.close()
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.animationDuration
      closing.animator().alphaValue = 0
    } completionHandler: {
      MainRunLoopDelivery.perform {
        closing.orderOut(nil)
        closing.close()
      }
    }
  }
}
