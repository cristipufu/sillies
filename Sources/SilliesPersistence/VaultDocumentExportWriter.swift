import Foundation
import SilliesCore

/// Writes one document incrementally and publishes its folder only after every file is complete.
public final class VaultDocumentExportWriter {
  private let source: VaultFileStorage
  private let staging: VaultFileStorage
  private let finalURL: URL
  private let header: VaultDocumentHeader
  private var handle: FileHandle?

  public init(sourceDirectory: URL, destination: URL, header: VaultDocumentHeader) throws {
    guard destination.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
    self.header = header
    source = VaultFileStorage(directory: sourceDirectory)
    let name = "Sillies-\(header.id.uuidString)-\(UUID().uuidString.prefix(8))"
    finalURL = destination.appendingPathComponent(name, isDirectory: true)
    staging = VaultFileStorage(
      directory: destination.appendingPathComponent(".\(name).partial", isDirectory: true))
    try staging.write(Data(), named: "Note.md")
    handle = try FileHandle(forWritingTo: staging.url(for: "Note.md"))
    let title = header.title.replacingOccurrences(of: "\n", with: " ")
    try append("# \(title)\n\n\(header.source.createdAt.ISO8601Format())\n")
    if let link = header.metadata.link { try append("\nSource: \(link.url.absoluteString)\n") }
    if !header.metadata.tags.isEmpty {
      try append("\nTags: \(header.metadata.tags.joined(separator: ", "))\n")
    }
  }

  public func beginSection(_ section: VaultDocumentSection) throws {
    try append("\n\n## \(Self.heading(section))\n\n")
  }
  public func append(_ text: String) throws {
    guard let handle else { throw CocoaError(.fileWriteUnknown) }
    try handle.write(contentsOf: Data(text.utf8))
  }

  public func finish() throws -> URL {
    let attachments = [
      header.source.imageFilename, header.source.audioFilename, header.metadata.link?.imageFilename,
    ].compactMap { $0 }
    for filename in Set(attachments).sorted() {
      try source.copyAttachment(named: filename, to: staging)
      let escaped =
        filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
      try append("\n\n[\(filename)](\(escaped))\n")
    }
    try handle?.synchronize()
    try handle?.close()
    handle = nil
    try FileManager.default.moveItem(at: staging.directory, to: finalURL)
    return finalURL
  }

  public func abandon() {
    do { try handle?.close() } catch {
      fputs("Could not close partial Vault export: \(error)\n", stderr)
    }
    handle = nil
    do { try FileManager.default.removeItem(at: staging.directory) } catch {
      fputs("Could not remove partial Vault export: \(error)\n", stderr)
    }
  }

  // localization-exempt: stable Markdown export headings, matching the existing export contract.
  private static func heading(_ section: VaultDocumentSection) -> String {
    switch section {
    case .notes: "My Notes"
    case .summary: "Summary"
    case .transcript: "Transcript"
    case .screenshotText: "Screenshot Text"
    case .explanation: "Explanation"
    case .actions: "Action Items"
    case .suggestions: "Meeting Suggestions"
    case .stash: "Saved Text"
    case .linkText: "Link Preview"
    case .originalTranscript: "Original Transcript"
    case .title: "Title"
    case .labels: "Tags"
    case .files: "File references"
    }
  }
}
