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
    chooser.prompt = String(localized: "Export here")
    chooser.message = String(
      localized: "Each session gets a folder with Markdown and its saved attachments.")
    chooser.begin { [library] response in
      guard response == .OK, let destination = chooser.url else { return }
      Task {
        do {
          let count = try await library.export(selection, to: destination)
          completion(String(localized: "Exported \(count) session(s)", comment: "plural"))
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
}
