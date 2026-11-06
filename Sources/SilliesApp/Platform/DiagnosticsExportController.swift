import AppKit
import UniformTypeIdentifiers

@MainActor final class DiagnosticsExportController {
  private let dialog = NativeFileDialog()

  func chooseFile(for model: DiagnosticsPresentation, parent: NSWindow) {
    guard !dialog.isPresented, !model.isBusy else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Sillies-Diagnostics.json"
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Export diagnostics")
    dialog.choose(panel, for: parent) { destination in
      guard let destination else { return }
      Task { await model.export(to: destination) }
    }
  }
  func cancel() { dialog.cancel() }
}
