import AppKit
import SilliesVault

@MainActor final class VaultExportController {
  private let library: VaultLibrary
  private let dialog = NativeFileDialog()
  private var task: Task<Void, Never>?
  private enum Request {
    case markdown(VaultExportSelection)
    case backup
    case text(String)
  }
  init(library: VaultLibrary) { self.library = library }
  func chooseFolder(
    _ selection: VaultExportSelection, parent: NSWindow, completion: @escaping (String?) -> Void
  ) {
    choose(.markdown(selection), parent: parent, completion: completion)
  }
  func chooseBackup(parent: NSWindow, completion: @escaping (String?) -> Void) {
    choose(.backup, parent: parent, completion: completion)
  }
  func chooseTextExport(_ text: String, parent: NSWindow, completion: @escaping (String?) -> Void) {
    choose(.text(text), parent: parent, completion: completion)
  }
  private func choose(_ request: Request, parent: NSWindow, completion: @escaping (String?) -> Void)
  {
    guard !dialog.isPresented, task == nil else {
      completion(nil)
      return
    }
    let chooser = NSOpenPanel()
    chooser.canChooseFiles = false
    chooser.canChooseDirectories = true
    chooser.canCreateDirectories = true
    chooser.prompt = String(localized: "Export here")
    switch request {
    case .text:
      chooser.message = String(localized: "Save the selected text as a Markdown file.")
    case .markdown:
      chooser.message = String(
        localized: "Each session gets a folder with Markdown and its saved attachments.")
    case .backup:
      chooser.message = String(
        localized:
          "Back up Vault items, drafts and saved files, including Trash. Companion conversations and downloaded models are stored separately."
      )
    }
    dialog.choose(chooser, for: parent) { [weak self] destination in
      guard let self, let destination else {
        completion(nil)
        return
      }
      self.task = Task { [weak self, library = self.library] in
        defer { self?.task = nil }
        do {
          switch request {
          case .text(let text):
            _ = try await library.exportText(text, to: destination)
            try Task.checkCancellation()
            completion(String(localized: "Selected text exported"))
          case .markdown(let selection):
            let count = try await library.export(selection, to: destination)
            try Task.checkCancellation()
            completion(String(localized: "Exported \(count) session(s)", comment: "plural"))
          case .backup:
            _ = try await library.backup(to: destination)
            try Task.checkCancellation()
            completion(String(localized: "Vault backup saved"))
          }
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
  @discardableResult func cancel() -> Task<Void, Never>? {
    let pending = task
    dialog.cancel()
    pending?.cancel()
    return pending
  }
  isolated deinit { cancel() }
}
