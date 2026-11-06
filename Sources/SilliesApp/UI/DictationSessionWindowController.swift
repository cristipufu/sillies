import AppKit
import SilliesWriting
import SwiftUI

/// A familiar session window that opens only on request and preserves the destination app's focus.
@MainActor final class DictationSessionWindowController {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

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
      panel.title = String(localized: "Sillies · Dictate")
      panel.isReleasedWhenClosed = false
      panel.hidesOnDeactivate = false
      panel.becomesKeyOnlyIfNeeded = true
      AppContentWindowStacking.shared.register(panel)
      appearance.register(panel)
      panel.contentMinSize = SessionWindowLayout.minimumSize
      let host = ThemedHostingController(
        rootView: DictationSessionView(
          model: model, companionName: companionName, copy: copy, history: history),
        appearance: appearance)
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
