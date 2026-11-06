import AppKit
import SilliesChat
import UniformTypeIdentifiers

@MainActor final class ConversationExportController {
  private var chooser: NSSavePanel?

  func chooseFile(for model: ConversationExport, parent: NSWindow) {
    guard chooser == nil, model.isAvailable, !model.isExporting else { return }
    let panel = NSSavePanel()
    chooser = panel
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.nameFieldStringValue = "Sillies-Conversation.md"
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Export conversation")
    panel.message = String(
      localized: "Save this companion’s messages as Markdown. Memories and drafts are not included."
    )
    panel.beginSheetModal(for: parent) { [weak self] response in
      self?.chooser = nil
      guard response == .OK, let destination = panel.url else { return }
      model.start(to: destination)
    }
  }

  func cancel() { chooser?.cancel(nil) }
}
