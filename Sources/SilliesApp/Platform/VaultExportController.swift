import AppKit
import SilliesCore
import SilliesPersistence

private actor VaultExportWorker {
  func export(_ records: [SessionRecord], source: URL, destination: URL) throws {
    let exporter = VaultMarkdownExporter(sourceDirectory: source)
    for record in records {
      try Task.checkCancellation()
      _ = try exporter.export(record, to: destination)
    }
  }
}

@MainActor final class VaultExportController {
  private let worker = VaultExportWorker()
  func chooseFolder(records: [SessionRecord], source: URL, completion: @escaping (String) -> Void) {
    guard !records.isEmpty else { return }
    let chooser = NSOpenPanel()
    chooser.canChooseFiles = false
    chooser.canChooseDirectories = true
    chooser.canCreateDirectories = true
    chooser.prompt = "Export here"
    chooser.message = "Each session gets a folder with Markdown and its saved attachments."
    chooser.begin { [worker] response in
      guard response == .OK, let destination = chooser.url else { return }
      Task {
        do {
          try await worker.export(records, source: source, destination: destination)
          completion("Exported \(records.count) session(s)")
        } catch {
          fputs("Vault export failed: \(error)\n", stderr)
          completion(
            "Export stopped: \(error.localizedDescription). Completed folders remain available.")
        }
      }
    }
  }
}
