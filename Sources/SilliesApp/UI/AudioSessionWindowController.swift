import AppKit
import SwiftUI

@MainActor
final class AudioSessionWindowController {
  private static let initialSize = CGSize(width: 640, height: 760)
  private static let minimumSize = CGSize(width: 560, height: 640)
  private(set) var window: CompanionUtilityWindow?
  private weak var displayedSession: AudioSessionPresentation?

  func show(_ model: AudioSessionPresentation) {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: Self.initialSize),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentMinSize = Self.minimumSize
      window.center()
      self.window = window
    }
    window?.title = "Sillies · \(model.kind.title)"
    if displayedSession !== model {
      window?.contentView = NSHostingView(rootView: AudioSessionView(model: model))
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
