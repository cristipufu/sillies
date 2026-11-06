import AppKit
import UniformTypeIdentifiers

@MainActor final class DiagnosticsExportController {
  private var chooser: NSSavePanel?

  func chooseFile(for model: DiagnosticsPresentation) {
    guard chooser == nil, !model.isBusy else { return }
    let panel = NSSavePanel()
    chooser = panel
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Sillies-Diagnostics.json"
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Export diagnostics")
    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      self?.chooser = nil
      guard response == .OK, let destination = panel.url else { return }
      Task { await model.export(to: destination) }
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }
}
