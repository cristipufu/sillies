import Foundation

/// Conservative model/working-set estimate; same-turn overlap must leave headroom for macOS.
package struct InferenceReservation: Sendable {
  package let conversationID: UUID?
  package let bytes: UInt64
  package init(conversationID: UUID? = nil, modelBytes: Int64 = 0) {
    self.conversationID = conversationID
    let weights = UInt64(max(0, modelBytes))
    let workspace = max(2 * 1_024 * 1_024 * 1_024, weights / 2)
    let sum = weights.addingReportingOverflow(workspace)
    bytes = modelBytes == 0 ? 0 : sum.overflow ? .max : sum.partialValue
  }
  package func canOverlap(_ other: Self, budget: UInt64) -> Bool {
    conversationID != nil && conversationID == other.conversationID
      && bytes <= budget && other.bytes <= budget - bytes
  }
}
