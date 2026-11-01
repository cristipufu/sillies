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
  private var anchor: WritingCompanionAnchor?
  private weak var displayedSession: ChatSession?
  var prefersReducedMotion: () -> Bool = { false }
  private var reducesMotion: Bool {
    prefersReducedMotion() || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func show(
    _ model: ChatSession, openSettings: @escaping (ChatNotice.SettingsDestination) -> Void,
    renderer: String? = nil, vault: ChatVaultPresentation? = nil,
    anchor: WritingCompanionAnchor? = nil
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
      appearance.register(window)
      window.center()
      self.window = window
    }
    if let anchor { attach(to: anchor) }
    window?.title = String(localized: "Sillies · Chat with \(model.companionName)")
    if displayedSession !== model {
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
    reveal()
    NSApp.activate(ignoringOtherApps: true)
  }
  func attach(to anchor: WritingCompanionAnchor) {
    self.anchor = anchor
    guard let window else { return }
    window.contentMinSize =
      displayedSession?.mode == .talk ? ChatWindowLayout.talkSize : ChatWindowLayout.minimumSize
    let visible = CompanionPanel.visibleFrame(
      for: NSScreen.screens.first { $0.frame.contains(anchor.position) })
    let layout = ConversationBubbleLayout(
      anchor: anchor.position,
      size: displayedSession?.mode == .talk
        ? ChatWindowLayout.talkSize : ChatWindowLayout.initialSize, visibleFrame: visible)
    bubble.tail = layout.tail
    bubble.tailOffset = layout.tailOffset
    window.setFrame(layout.frame, display: false)
  }
  private func observeMode(_ model: ChatSession) {
    withObservationTracking {
      _ = model.mode
      if let anchor { attach(to: anchor) }
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
    window.contentView?.layoutSubtreeIfNeeded()
    if let editor = composer(in: window.contentView) { window.makeFirstResponder(editor) }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animate ? Self.animationDuration : 0
      window.animator().alphaValue = 1
      window.animator().setFrame(target, display: false)
    }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    displayedSession?.onFinish?()
    if window != nil { close() }
    return false
  }
  func windowWillClose(_ notification: Notification) { displayedSession?.stopVoiceConversation() }
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
