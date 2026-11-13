import Foundation
import SilliesCore
import SilliesPersistence
import SilliesReasoning

extension VaultLibrary {
  package func notesInput(id: UUID) throws -> VaultNotesInput? {
    try Task.checkCancellation()
    return try storage().notesInput(id: id)
  }

  package func completeNotes(id: UUID, notes: LocalNotes, revision: VaultNotesInput.Revision) throws
    -> VaultSnapshot?
  {
    let edit = VaultRecordEdit.completeNotes(notes, revision: revision)
    guard try storage().editNotes(id: id, revision: revision, apply: edit.apply) else { return nil }
    cache.remove(id)
    searchRevision = UUID()
    scheduleIndex()
    return try snapshot()
  }
}
