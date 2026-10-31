import AppKit
import SilliesChat
import SwiftUI

@MainActor final class ChatSessionWindowController {
  private(set) var window: CompanionUtilityWindow?
  private weak var displayedSession: ChatSession?

  func show(_ model: ChatSession, openSettings: @escaping (ChatNotice.SettingsDestination) -> Void)
  {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: SessionWindowLayout.initialSize),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentMinSize = SessionWindowLayout.minimumSize
      window.level = .normal
      AppContentWindowStacking.shared.register(window)
      window.center()
      self.window = window
    }
    window?.title = "Sillies · Chat with \(model.companionName)"
    if displayedSession !== model {
      let view = NSHostingView(rootView: ChatSessionView(model: model, openSettings: openSettings))
      view.sizingOptions = []
      window?.contentView = view
      displayedSession = model
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func close() {
    window?.close()
    window = nil
    displayedSession = nil
  }
}
