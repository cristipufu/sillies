import Foundation
import SilliesCore

public struct VaultMarkdownExporter: Sendable {
  private let source: VaultFileStorage
  public init(sourceDirectory: URL) { source = VaultFileStorage(directory: sourceDirectory) }

  public func export(_ record: SessionRecord, to directory: URL) throws -> URL {
    let name = "Sillies-\(record.id.uuidString)-\(UUID().uuidString.prefix(8))"
    let destination = VaultFileStorage(
      directory: directory.appendingPathComponent(name, isDirectory: true))
    var markdown = SessionMarkdownFormatter.format(record)
    for filename in [record.imageFilename, record.audioFilename].compactMap({ $0 }) {
      try source.copyAttachment(named: filename, to: destination)
      let escaped =
        filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
      markdown +=
        record.imageFilename == filename
        ? "\n\n![Screenshot](\(escaped))\n" : "\n\n[Recording](\(escaped))\n"
    }
    try destination.write(Data(markdown.utf8), named: "Note.md")
    return try destination.url(for: "Note.md")
  }
}
