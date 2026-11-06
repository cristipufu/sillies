import Foundation
import SilliesCore
import SilliesPersistence

/// Serial, lazy storage access. No UI actor or model runtime can own the database connection.
package actor ConversationLibrary: ConversationRepository, CompanionMemoryRepository,
  CompanionMemoryEditing, PersonalFactsRepository, ConversationDataManaging
{
  let directory: URL
  private let searches: ConversationSearchWorker
  private var database: ConversationDatabase?
  private var searchGeneration = UUID()
  var memorySearchGeneration = UUID()
  var memoryEmbeddings: SearchEmbeddingAccess?
  var memoryIndexTask: Task<Void, Never>?
  var memoryIndexGeneration = UUID()
  var memoryIndexFailure: String?
  package init(directory: URL) {
    self.directory = directory
    searches = ConversationSearchWorker(directory: directory)
  }

  func storage() throws -> ConversationDatabase {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if let database { return database }
    let opened = try ConversationDatabase(directory: directory)
    database = opened
    return opened
  }

  package func open(_ owner: ConversationOwner) throws -> ConversationSnapshot {
    try storage().open(owner)
  }
  package func save(_ update: ConversationUpdate) throws { try storage().save(update) }
  package func checkpoint(_ handle: ConversationHandle) throws -> ConversationMemorySnapshot {
    try Task.checkCancellation()
    return try storage().checkpoint(handle)
  }
  package func advanceCheckpoint(_ update: ConversationMemoryUpdate) throws -> Bool {
    try Task.checkCancellation()
    return try storage().advanceCheckpoint(update)
  }
  package func page(_ request: ConversationPageRequest) throws -> ConversationPage {
    try Task.checkCancellation()
    return try storage().page(request)
  }
  package func search(_ request: ConversationSearchRequest) async throws
    -> [ConversationSearchMatch]
  {
    try Task.checkCancellation()
    _ = try storage()
    let generation = searchGeneration
    let results = try await searches.search(request)
    try Task.checkCancellation()
    guard generation == searchGeneration else { throw ConversationStorageError.changed }
    return results
  }
  package func conversations() throws -> [ConversationHeader] { try storage().conversations() }
  package func clear(_ handle: ConversationHandle) throws -> ConversationSnapshot {
    try removeConversationData(.messagesAndMemories, handle: handle)
  }
  package func removeConversationData(
    _ removal: ConversationDataRemoval, handle: ConversationHandle
  ) throws -> ConversationSnapshot {
    let snapshot = try storage().removeConversationData(removal, handle: handle)
    searchGeneration = UUID()
    memorySearchGeneration = UUID()
    scheduleMemoryIndex()
    return snapshot
  }
  package func memories(_ query: CompanionMemoryQuery) async throws -> [CompanionMemory] {
    try Task.checkCancellation()
    _ = try storage()
    let generation = memorySearchGeneration
    let keywords = try await searches.memories(query)
    var related: [CompanionMemory] = []
    if let access = memoryEmbeddings,
      !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      do {
        related = try await SemanticSearchDeadline.perform { [searches] in
          guard let embedding = try await access.embed(.init(text: query.text, purpose: .query))
          else { return [] }
          return try await searches.semanticMemories(
            query, embedding: embedding, provider: access.identity)
        }
      } catch is CancellationError { try Task.checkCancellation() } catch SearchEmbeddingError
        .unavailable
      {
        // Keywords remain available during preparation or a deadline.
      } catch {
        fputs("Semantic memory search unavailable: \(error)\n", stderr)
      }
    }
    let result = MemorySearchFusion.merge(keywords: keywords, semantic: related, limit: query.limit)
    try Task.checkCancellation()
    guard generation == memorySearchGeneration else { throw ConversationStorageError.changed }
    return result
  }
  package func memoryPage(_ request: CompanionMemoryPageRequest) throws -> CompanionMemoryPage {
    try Task.checkCancellation()
    return try storage().memoryPage(request)
  }
  package func remember(_ request: MemoryWrite) throws -> MemoryReceipt {
    let receipt = try storage().remember(request)
    memorySearchGeneration = UUID()
    scheduleMemoryIndex()
    return receipt
  }
  package func correctMemory(_ correction: MemoryCorrection) throws -> MemoryCorrectionResult {
    let result = try storage().correctMemory(correction)
    memorySearchGeneration = UUID()
    scheduleMemoryIndex()
    return result
  }
  package func forget(_ handle: ConversationHandle, id: UUID) throws -> ConversationSnapshot {
    let snapshot = try storage().forget(handle, id: id)
    memorySearchGeneration = UUID()
    scheduleMemoryIndex()
    return snapshot
  }
  package func undoMemory(_ handle: ConversationHandle, receiptID: UUID) throws
    -> ConversationSnapshot
  {
    let snapshot = try storage().undoMemory(handle, receiptID: receiptID)
    memorySearchGeneration = UUID()
    scheduleMemoryIndex()
    return snapshot
  }
  package func recentMemoryChanges(_ handle: ConversationHandle) throws -> [MemoryReceipt] {
    try storage().recentMemoryChanges(handle)
  }
}
