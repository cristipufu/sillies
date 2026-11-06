import Foundation

/// An explicit human edit, separate from model-authored writes backed by a quoted message.
public struct MemoryCorrection: Sendable {
  public let handle: ConversationHandle
  public let target: CompanionMemory.Reference
  public let value: String
  public let savedAt: Date
  public init(
    handle: ConversationHandle, target: CompanionMemory.Reference, value: String, savedAt: Date
  ) {
    self.handle = handle
    self.target = target
    self.value = value
    self.savedAt = savedAt
  }
}

public struct MemoryCorrectionResult: Sendable {
  public let snapshot: ConversationSnapshot
  public let receipt: MemoryReceipt
  public init(snapshot: ConversationSnapshot, receipt: MemoryReceipt) {
    self.snapshot = snapshot
    self.receipt = receipt
  }
}

public protocol CompanionMemoryEditing: Sendable {
  func correctMemory(_ correction: MemoryCorrection) async throws -> MemoryCorrectionResult
}
