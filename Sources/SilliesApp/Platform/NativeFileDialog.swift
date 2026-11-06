import AppKit

/// One parent-scoped chooser. Late native completions cannot finish a newer request.
@MainActor final class NativeFileDialog {
  typealias Present = (NSSavePanel, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) ->
    Void
  private struct Request {
    let id: UUID
    let panel: NSSavePanel
    let parentClosed: NSObjectProtocol
    let completion: (URL?) -> Void
  }
  private let present: Present
  private var request: Request?
  var isPresented: Bool { request != nil }

  init(
    present: @escaping Present = { panel, parent, completion in
      panel.beginSheetModal(for: parent, completionHandler: completion)
    }
  ) {
    self.present = present
  }

  func choose(_ panel: NSSavePanel, for parent: NSWindow, completion: @escaping (URL?) -> Void) {
    guard request == nil, parent.attachedSheet == nil else {
      completion(nil)
      return
    }
    let id = UUID()
    let observer = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: parent, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
    request = Request(id: id, panel: panel, parentClosed: observer, completion: completion)
    present(panel, parent) { [weak self, weak panel] response in
      self?.finish(id, destination: response == .OK ? panel?.url : nil)
    }
  }

  private func finish(_ id: UUID, destination: URL?) {
    guard let current = request, current.id == id else { return }
    request = nil
    NotificationCenter.default.removeObserver(current.parentClosed)
    current.completion(destination)
  }

  func cancel() {
    guard let current = request else { return }
    finish(current.id, destination: nil)
    current.panel.cancel(nil)
  }

  isolated deinit { cancel() }
}
