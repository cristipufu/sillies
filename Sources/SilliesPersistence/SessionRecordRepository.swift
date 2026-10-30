import Foundation
import SilliesCore

/// Owns the on-disk session format. A failed read is never treated as an empty vault.
public struct SessionRecordRepository: Sendable {
  static let filename = "sessions.json"
  private let files: VaultFileStorage

  public init(directory: URL) { files = VaultFileStorage(directory: directory) }

  public func load() throws -> [SessionRecord] {
    let data: Data
    do {
      data = try Data(contentsOf: files.url(for: Self.filename))
    } catch CocoaError.fileReadNoSuchFile {
      return []
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let records = try decoder.decode([SessionRecord].self, from: data)
    try validateAttachments(in: records)
    return records
  }

  public func save(_ records: [SessionRecord]) throws {
    try validateAttachments(in: records)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try files.write(encoder.encode(records), named: Self.filename)
  }

  private func validateAttachments(in records: [SessionRecord]) throws {
    for record in records {
      for filename in [record.imageFilename, record.audioFilename].compactMap({ $0 }) {
        _ = try files.attachmentURL(for: filename)
      }
    }
  }
}
