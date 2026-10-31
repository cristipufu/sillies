import AppKit
import SwiftUI

/// A familiar session window that opens only on request and preserves the destination app's focus.
@MainActor final class DictationSessionWindowController {
  private(set) var window: NSPanel?

  func show(
    _ model: DictationCoordinator, companionName: String,
    copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    if window == nil {
      let panel = NSPanel(
        contentRect: CGRect(origin: .zero, size: SessionWindowLayout.initialSize),
        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
        backing: .buffered, defer: false)
      panel.title = "Sillies · Dictate"
      panel.isReleasedWhenClosed = false
      panel.hidesOnDeactivate = false
      panel.becomesKeyOnlyIfNeeded = true
      panel.level = CompanionPanel.contentWindowLevel
      panel.contentMinSize = SessionWindowLayout.minimumSize
      let host = NSHostingController(
        rootView: DictationSessionView(
          model: model, companionName: companionName, copy: copy, history: history))
      host.sizingOptions = []
      panel.contentViewController = host
      panel.center()
      window = panel
    }
    window?.orderFrontRegardless()
  }
  func close() {
    window?.close()
    window = nil
  }
}
