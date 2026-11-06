import AppKit
import SwiftUI

private struct SavedTranscriptView: View {
  @Environment(\.silliesTheme) private var theme
  let text: String
  var body: some View {
    LiveTranscriptTextView(text: text, followsLive: .constant(false))
      .padding(22).frame(minWidth: 520, minHeight: 320)
      .background(theme.paper)
  }
}

@MainActor final class SavedTranscriptWindow {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  private(set) var window: NSWindow?
  private var displayedID: UUID?
  private var displayedText: String?
  func show(_ text: String, title: String, id: UUID) {
    prepare(text, title: title, id: id)
    window?.makeKeyAndOrderFront(nil)
  }
  func prepare(_ text: String, title: String, id: UUID) {
    if window == nil {
      let created = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 720, height: 580),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      created.isReleasedWhenClosed = false
      AppContentWindowStacking.shared.register(created)
      appearance.register(created)
      created.center()
      window = created
    }
    window?.title = title
    if displayedID != id || displayedText != text {
      displayedID = id
      displayedText = text
      window?.contentViewController = ThemedHostingController(
        rootView: SavedTranscriptView(text: text), appearance: appearance)
    }
  }
  func close() {
    window?.close()
    window = nil
    displayedID = nil
    displayedText = nil
  }
  isolated deinit { close() }
}
