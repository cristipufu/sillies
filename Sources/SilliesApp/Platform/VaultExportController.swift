import AppKit
import SilliesVault

@MainActor final class VaultExportController {
  private let library: VaultLibrary
  init(library: VaultLibrary) { self.library = library }
  func chooseFolder(_ selection: VaultExportSelection, completion: @escaping (String) -> Void) {
    let chooser = NSOpenPanel()
    chooser.canChooseFiles = false
    chooser.canChooseDirectories = true
    chooser.canCreateDirectories = true
    chooser.prompt = "Export here"
    chooser.message = "Each session gets a folder with Markdown and its saved attachments."
    chooser.begin { [library] response in
      guard response == .OK, let destination = chooser.url else { return }
      Task {
        do {
          let count = try await library.export(selection, to: destination)
          completion("Exported \(count) session(s)")
        } catch {
          fputs("Vault export failed: \(error)\n", stderr)
          completion(
            "Export stopped: \(error.localizedDescription). Completed folders remain available.")
        }
      }
    }
  }
}
