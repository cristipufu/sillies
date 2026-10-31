import AppKit
import SwiftUI

private struct SavedTranscriptView: View {
  let text: String
  var body: some View {
    LiveTranscriptTextView(text: text, followsLive: .constant(false))
      .padding(22).frame(minWidth: 520, minHeight: 320)
      .background(SilliesTheme.paper)
  }
}

@MainActor final class SavedTranscriptWindow {
  private var window: NSWindow?
  func show(_ text: String, title: String) {
    if window == nil {
      let created = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 720, height: 580),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      created.isReleasedWhenClosed = false
      created.center()
      window = created
    }
    window?.title = title
    window?.contentViewController = NSHostingController(rootView: SavedTranscriptView(text: text))
    window?.makeKeyAndOrderFront(nil)
  }
}
