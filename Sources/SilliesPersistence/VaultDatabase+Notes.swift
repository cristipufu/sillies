import Foundation
import SilliesCore

extension VaultDatabase {
  public func notesInput(id: UUID) throws -> VaultNotesInput? {
    try sql.readSnapshot { try sql.cancellableRead { try readNotesInput(id: id) } }
  }

  /// Field edits and source validation share the write transaction; a stale job cannot publish.
  public func editNotes(
    id: UUID, revision: VaultNotesInput.Revision,
    apply: (inout SessionRecord) -> Bool
  ) throws -> Bool {
    try Task.checkCancellation()
    return try sql.transaction {
      guard let header = try notesHeader(id: id), header.source.summaryPending,
        var current = try record(id: id),
        try notesRevision(id: id, generation: current.processingRevision.notes) == revision
      else { return false }
      guard apply(&current) else { return false }
      try store(current)
      return true
    }
  }

  private func readNotesInput(id: UUID) throws -> VaultNotesInput? {
    guard try notesHeader(id: id) != nil, let record = try record(id: id)
    else { return nil }
    return try .init(
      record: record, personalNotes: authoredNotes(recordID: id),
      revision: notesRevision(id: id, generation: record.processingRevision.notes))
  }

  private func notesHeader(id: UUID) throws -> VaultDocumentHeader? {
    guard let header = try documentHeader(id: id), header.metadata.trashedAt == nil else {
      return nil
    }
    return header
  }

  private func notesRevision(id: UUID, generation: UUID) throws -> VaultNotesInput.Revision {
    try .init(
      generation: generation,
      transcript: sectionRevision(.init(recordID: id, section: .transcript)),
      screenshotText: sectionRevision(.init(recordID: id, section: .screenshotText)),
      personalNotes: sectionRevision(.init(recordID: id, section: .notes)))
  }
}
