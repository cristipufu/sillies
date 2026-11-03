import Foundation
import SilliesCore
import SilliesPersistence

/// Serial, lazy storage access. No UI actor or model runtime can own the database connection.
package actor ConversationLibrary: ConversationRepository, CompanionMemoryRepository {
  private let directory: URL
  private var database: ConversationDatabase?
  package init(directory: URL) { self.directory = directory }

  private func storage() throws -> ConversationDatabase {
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
  package func search(_ request: ConversationSearchRequest) throws -> [ConversationSearchMatch] {
    try Task.checkCancellation()
    return try storage().search(request)
  }
  package func conversations() throws -> [ConversationHeader] { try storage().conversations() }
  package func clear(_ handle: ConversationHandle) throws -> ConversationSnapshot {
    try storage().clear(handle)
  }
  package func memories(_ handle: ConversationHandle, query: String) throws -> [CompanionMemory] {
    try storage().memories(handle, query: query)
  }
  package func remember(_ request: MemoryWrite) throws -> MemoryReceipt {
    try storage().remember(request)
  }
  package func forget(_ handle: ConversationHandle, id: UUID) throws -> ConversationSnapshot {
    try storage().forget(handle, id: id)
  }
  package func undoMemory(_ handle: ConversationHandle, receiptID: UUID) throws
    -> ConversationSnapshot
  {
    try storage().undoMemory(handle, receiptID: receiptID)
  }
  package func recentMemoryChanges(_ handle: ConversationHandle) throws -> [MemoryReceipt] {
    try storage().recentMemoryChanges(handle)
  }
}
