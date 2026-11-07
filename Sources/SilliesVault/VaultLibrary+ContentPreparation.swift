import Foundation
import SilliesCore

extension VaultLibrary {
  private static var contentYield: Duration { .milliseconds(20) }

  package func resumeContentPreparation() {
    guard contentTask == nil else { return }
    let generation = UUID()
    contentGeneration = generation
    contentFailure = nil
    contentTask = Task { [weak self] in
      await self?.prepareContent(generation: generation)
    }
  }

  package func stopContentPreparation() {
    contentGeneration = UUID()
    contentTask?.cancel()
    contentTask = nil
  }

  private func prepareContent(generation: UUID) async {
    defer { if contentGeneration == generation { contentTask = nil } }
    do {
      while contentGeneration == generation {
        try Task.checkCancellation()
        guard try storage().prepareNextContent() else { return }
        scheduleIndex()
        try await Task.sleep(for: Self.contentYield)
      }
    } catch is CancellationError { return } catch {
      contentFailure = error.localizedDescription
      fputs("Vault section preparation failed: \(error)\n", stderr)
    }
  }

  package func prepareDocument(id: UUID) throws { try storage().prepareContent(id: id) }
  package func metadataDraft(id: UUID) throws -> VaultMetadataDraft? {
    try storage().metadataDraft(id: id)
  }
  package func saveMetadataDraft(_ draft: VaultMetadataDraft) throws {
    try storage().saveMetadataDraft(draft)
  }
  package func commitMetadataDraft(_ draft: VaultMetadataDraft, at date: Date) throws
    -> VaultDocumentHeader
  {
    let header = try storage().commitMetadataDraft(draft, at: date)
    cache.remove(draft.recordID)
    searchRevision = UUID()
    scheduleIndex()
    return header
  }
  package func draft(_ location: VaultBlockLocation) throws -> VaultDraft? {
    try storage().draft(location)
  }
  package func saveDraft(_ draft: VaultDraft) throws { try storage().saveDraft(draft) }
  package func discardDraft(_ location: VaultBlockLocation) throws {
    try storage().discardDraft(location)
  }
  package func commitDraft(_ draft: VaultDraft, at date: Date) throws -> VaultDraftCommit {
    let committed = try storage().commitDraft(draft, at: date)
    cache.remove(draft.location.recordID)
    searchRevision = UUID()
    scheduleIndex()
    return committed
  }
}
