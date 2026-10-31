import Foundation
import SilliesCore

/// Commits attachments before their index, and removes files only after the index stops referring to them.
/// The journal makes interrupted cleanup recoverable without scanning or deleting unrelated files.
public struct VaultCommitRepository: Sendable {
  public static let journalFilename = "pending-attachments.json"
  public struct Attachment: Sendable {
    public let filename: String
    public let data: Data
    public init(filename: String, data: Data) {
      self.filename = filename
      self.data = data
    }
  }
  private let files: VaultFileStorage
  private let records: SessionRecordRepository
  private let writeIndex: @Sendable ([SessionRecord]) throws -> Void

  public init(directory: URL) {
    files = VaultFileStorage(directory: directory)
    records = SessionRecordRepository(directory: directory)
    let repository = records
    writeIndex = { try repository.save($0) }
  }

  init(directory: URL, writeIndex: @escaping @Sendable ([SessionRecord]) throws -> Void) {
    files = VaultFileStorage(directory: directory)
    records = SessionRecordRepository(directory: directory)
    self.writeIndex = writeIndex
  }

  public func load() throws -> [SessionRecord] {
    let saved = try records.load()
    try cleanJournal(referencedBy: saved)
    return saved
  }

  public func commit(
    _ snapshot: [SessionRecord], attachments: [Attachment], removing: Set<String>
  ) throws {
    let candidates = try readJournal().union(removing).union(attachments.map(\.filename))
    for filename in candidates { _ = try files.attachmentURL(for: filename) }
    if !candidates.isEmpty { try writeJournal(candidates) }
    for attachment in attachments {
      try files.write(attachment.data, named: attachment.filename)
    }
    try writeIndex(snapshot)
    try cleanJournal(referencedBy: snapshot)
  }

  private func cleanJournal(referencedBy snapshot: [SessionRecord]) throws {
    let candidates = try readJournal()
    guard !candidates.isEmpty else { return }
    let referenced = Set(
      snapshot.flatMap { [$0.imageFilename, $0.audioFilename].compactMap { $0 } })
    for filename in candidates.subtracting(referenced) {
      try files.removeAttachment(named: filename)
    }
    try writeJournal([])
  }

  private func readJournal() throws -> Set<String> {
    let data: Data
    do { data = try Data(contentsOf: files.url(for: Self.journalFilename)) } catch CocoaError
      .fileReadNoSuchFile
    {
      return []
    }
    return try JSONDecoder().decode(Set<String>.self, from: data)
  }

  private func writeJournal(_ filenames: Set<String>) throws {
    try files.write(JSONEncoder().encode(filenames.sorted()), named: Self.journalFilename)
  }
}
