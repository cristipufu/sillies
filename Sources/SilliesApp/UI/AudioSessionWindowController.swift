import AppKit
import SwiftUI

@MainActor
final class AudioSessionWindowController: NSObject, NSWindowDelegate {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  private(set) var window: CompanionUtilityWindow?
  private weak var displayedSession: AudioSessionPresentation?

  func show(_ model: AudioSessionPresentation) {
    prepare(model)
    model.showDetails()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func prepare(_ model: AudioSessionPresentation) {
    if window == nil {
      let window = CompanionUtilityWindow(
        contentRect: CGRect(origin: .zero, size: SessionWindowLayout.initialSize),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.contentMinSize = SessionWindowLayout.minimumSize
      window.center()
      self.window = window
    }
    window?.title = String(localized: "Sillies · \(model.kind.title)")
    if displayedSession !== model {
      displayedSession?.hideDetails()
      let view = ThemedHostingView(rootView: AudioSessionView(model: model), appearance: appearance)
      view.sizingOptions = []
      window?.contentView = view
      displayedSession = model
    }
  }

  func close() {
    displayedSession?.hideDetails()
    window?.close()
    window = nil
    displayedSession = nil
  }

  func windowWillClose(_ notification: Notification) {
    displayedSession?.hideDetails()
  }
}
