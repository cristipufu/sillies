import AppKit
import SwiftUI

@MainActor
final class AudioSessionWindowController {
  private(set) var window: CompanionUtilityWindow?
  private weak var displayedSession: AudioSessionPresentation?

  func show(_ model: AudioSessionPresentation) {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: SessionWindowLayout.initialSize),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentMinSize = SessionWindowLayout.minimumSize
      window.center()
      self.window = window
    }
    window?.title = "Sillies · \(model.kind.title)"
    if displayedSession !== model {
      let view = NSHostingView(rootView: AudioSessionView(model: model))
      view.sizingOptions = []
      window?.contentView = view
      displayedSession = model
    }
    model.hasUnreadSuggestion = false
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func close() {
    window?.close()
    window = nil
    displayedSession = nil
  }
}
