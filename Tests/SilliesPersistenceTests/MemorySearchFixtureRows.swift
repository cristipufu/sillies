import Foundation
import SilliesCore

@testable import SilliesPersistence

/// Seeds search corpora inside a caller-owned transaction, without per-fact undo bookkeeping.
/// Write, correction and recovery tests continue to exercise the public persistence APIs.
struct MemorySearchFixtureRows {
  let database: ConversationDatabase
  let owner: String

  func insertMemory(_ memory: CompanionMemory) throws {
    try database.sql.execute(
      "INSERT INTO companion_memories(id,owner,key,updated,body) VALUES(?,?,?,?,?)",
      [
        .text(memory.id.uuidString), .text(owner), .text(memory.key),
        .real(memory.savedAt.timeIntervalSince1970), .data(try database.encoder.encode(memory)),
      ])
  }

  func indexKeywords(_ memory: CompanionMemory) throws {
    try database.sql.execute(
      "INSERT INTO memory_search(id,text) VALUES(?,?)",
      [.text(memory.id.uuidString), .text(memory.key + " " + memory.value)])
  }

  func indexEmbedding(_ embedding: SearchEmbedding, memory: CompanionMemory, provider: String)
    throws
  {
    try database.sql.execute(
      "INSERT INTO memory_embeddings(provider,id,owner,space,vector) VALUES(?,?,?,?,?)",
      [
        .text(provider), .text(memory.id.uuidString), .text(owner), .text(embedding.space),
        .data(SearchVectorStorage.encode(embedding.values)),
      ])
  }
}
