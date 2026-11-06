import AppKit
import SilliesVault

@MainActor final class VaultExportController {
  private let library: VaultLibrary
  private let dialog = NativeFileDialog()
  private var task: Task<Void, Never>?
  init(library: VaultLibrary) { self.library = library }
  func chooseFolder(
    _ selection: VaultExportSelection, parent: NSWindow, completion: @escaping (String?) -> Void
  ) {
    guard !dialog.isPresented, task == nil else {
      completion(nil)
      return
    }
    let chooser = NSOpenPanel()
    chooser.canChooseFiles = false
    chooser.canChooseDirectories = true
    chooser.canCreateDirectories = true
    chooser.prompt = String(localized: "Export here")
    chooser.message = String(
      localized: "Each session gets a folder with Markdown and its saved attachments.")
    dialog.choose(chooser, for: parent) { [weak self] destination in
      guard let self, let destination else {
        completion(nil)
        return
      }
      self.task = Task { [weak self, library = self.library] in
        defer { self?.task = nil }
        do {
          let count = try await library.export(selection, to: destination)
          try Task.checkCancellation()
          completion(String(localized: "Exported \(count) session(s)", comment: "plural"))
        } catch is CancellationError {
          completion(nil)
        } catch {
          fputs("Vault export failed: \(error)\n", stderr)
          completion(
            String(
              localized:
                "Export stopped: \(error.localizedDescription). Completed folders remain available."
            ))
        }
      }
    }
  }
  func cancel() {
    dialog.cancel()
    task?.cancel()
  }
  isolated deinit { cancel() }
}
