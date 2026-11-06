import SilliesCore

/// Optional app capabilities; transient callers have no private-data provider.
package struct ConversationBackgroundAccess: Sendable {
  let materials: (any ConversationMaterialProviding)?
  let personalFacts: (any PersonalFactsRepository)?
  package init(
    materials: (any ConversationMaterialProviding)?, personalFacts: (any PersonalFactsRepository)?
  ) {
    self.materials = materials
    self.personalFacts = personalFacts
  }
  package static let empty = Self(materials: nil, personalFacts: nil)

  func prepare(_ context: ChatContext) async throws -> ChatContext {
    let records =
      try await materials?.selectedRecords(
        context.selectedRecords, query: context.messages.last?.text ?? "") ?? []
    try Task.checkCancellation()
    let facts: PersonalFactsSnapshot?
    if let handle = context.historyHandle {
      facts = try await personalFacts?.personalFacts(handle)
    } else {
      facts = nil
    }
    try Task.checkCancellation()
    return context.prepared(with: .init(records: records, personalFacts: facts))
  }
}
