import AppKit
import SilliesChat
import SwiftUI

enum ChatWindowLayout {
  static let initialSize = CGSize(width: 440, height: 660)
  static let minimumSize = CGSize(width: 380, height: 500)
}

@MainActor final class ChatSessionWindowController: NSObject, NSWindowDelegate {
  private static let animationDuration: TimeInterval = 0.18
  private static let entranceOffset: CGFloat = 14
  private var animationID = UUID()
  private(set) var window: CompanionUtilityWindow?
  private weak var displayedSession: ChatSession?
  var prefersReducedMotion: () -> Bool = { false }
  private var reducesMotion: Bool {
    prefersReducedMotion() || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func show(
    _ model: ChatSession, openSettings: @escaping (ChatNotice.SettingsDestination) -> Void,
    renderer: String? = nil
  ) {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: ChatWindowLayout.initialSize),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentMinSize = ChatWindowLayout.minimumSize
      window.delegate = self
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.level = .normal
      AppContentWindowStacking.shared.register(window)
      AppWindowAppearance.shared.register(window)
      window.center()
      self.window = window
    }
    window?.title = String(localized: "Sillies · Chat with \(model.companionName)")
    if displayedSession !== model {
      let view = NSHostingView(
        rootView: ChatSessionView(
          model: model, openSettings: openSettings, renderer: renderer,
          motion: reducesMotion ? .reduced : .animated))
      view.sizingOptions = []
      window?.contentView = view
      displayedSession = model
    }
    reveal()
    NSApp.activate(ignoringOtherApps: true)
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
    displayedSession?.stopVoiceConversation()
    guard !reducesMotion else { return true }
    let token = UUID()
    animationID = token
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.animationDuration
      sender.animator().alphaValue = 0
    } completionHandler: { [weak self, weak sender] in
      MainRunLoopDelivery.perform {
        guard self?.animationID == token else { return }
        sender?.orderOut(nil)
        sender?.alphaValue = 1
      }
    }
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
  func close() {
    animationID = UUID()
    window?.close()
    window = nil
    displayedSession = nil
  }
}
