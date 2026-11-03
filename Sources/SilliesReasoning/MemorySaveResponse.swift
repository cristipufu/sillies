import Foundation
import SilliesCore

/// Model-visible write acknowledgements describe committed state, independently of UI receipts.
struct MemorySaveResponse: Encodable {
  enum Status: String, Encodable { case saved, notSaved }
  enum Refusal: String, Encodable {
    case currentUserStatementRequired
    case invalidReplacementReference
    case replacementChanged
  }
  struct SavedMemory: Encodable {
    let memoryID: UUID
    let revision: UUID
    let key: String
    let value: String

    init(_ memory: CompanionMemory) {
      memoryID = memory.id
      revision = memory.revision
      key = memory.key
      value = memory.value
    }
  }

  let status: Status
  let memory: SavedMemory?
  let reason: Refusal?

  static func saved(_ receipt: MemoryReceipt) throws -> ConversationToolOutput {
    let full = Self(status: .saved, memory: .init(receipt.saved), reason: nil)
    let brief = Self(status: .saved, memory: nil, reason: nil)
    return try .init(text: full.encoded(), briefText: brief.encoded()).remembering(receipt)
  }

  static func refused(_ reason: Refusal) throws -> ConversationToolOutput {
    try .init(text: Self(status: .notSaved, memory: nil, reason: reason).encoded())
  }

  private func encoded() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }
}
