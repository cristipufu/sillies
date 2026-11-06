import AppKit
import SilliesChat
import UniformTypeIdentifiers

@MainActor final class ConversationExportController {
  private let dialog = NativeFileDialog()

  func chooseFile(for model: ConversationExport, parent: NSWindow) {
    guard !dialog.isPresented, model.isAvailable, !model.isExporting else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.nameFieldStringValue = "Sillies-Conversation.md"
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Export conversation")
    panel.message = String(
      localized: "Save this companion’s messages as Markdown. Memories and drafts are not included."
    )
    dialog.choose(panel, for: parent) { destination in
      guard let destination else { return }
      model.start(to: destination)
    }
  }

  func cancel() { dialog.cancel() }
}
