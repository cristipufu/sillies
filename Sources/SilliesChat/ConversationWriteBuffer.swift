import Foundation
import SilliesCore

/// Coalesces edits by message identity while preserving append order and failed payloads.
struct ConversationWriteBuffer {
  struct MessageEdit {
    let message: ChatMessage
    let revision: UInt64
  }
  private var order: [UUID] = []
  private var edits: [UUID: MessageEdit] = [:]
  private var removals: [UUID: UInt64] = [:]
  private(set) var revision: UInt64 = 0
  private(set) var savedRevision: UInt64 = 0
  var needsSave: Bool { revision != savedRevision }

  mutating func changedCheckpoint() { revision &+= 1 }
  mutating func stage(_ message: ChatMessage) {
    revision &+= 1
    if edits[message.id] == nil { order.append(message.id) }
    removals[message.id] = nil
    edits[message.id] = .init(message: message, revision: revision)
  }
  mutating func remove(_ id: UUID) {
    revision &+= 1
    edits[id] = nil
    order.removeAll { $0 == id }
    removals[id] = revision
  }
  func update(handle: ConversationHandle, checkpoint: ConversationCheckpoint, at date: Date)
    -> ConversationUpdate
  {
    .init(
      handle: handle, messages: order.compactMap { edits[$0]?.message }, checkpoint: checkpoint,
      removedMessageIDs: Set(removals.keys), savedAt: date)
  }
  mutating func acknowledge(_ completed: UInt64) {
    edits = edits.filter { $0.value.revision > completed }
    order.removeAll { edits[$0] == nil }
    removals = removals.filter { $0.value > completed }
    savedRevision = max(savedRevision, completed)
  }
}
