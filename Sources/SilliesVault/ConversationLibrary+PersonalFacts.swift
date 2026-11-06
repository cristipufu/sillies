import SilliesCore

extension ConversationLibrary {
  package func personalFacts(_ handle: ConversationHandle) throws -> PersonalFactsSnapshot {
    try Task.checkCancellation()
    return try storage().personalFacts(handle)
  }
  package func savePersonalFact(_ request: PersonalFactWrite) throws -> PersonalFactsSnapshot {
    try Task.checkCancellation()
    return try storage().savePersonalFact(request)
  }
  package func removePersonalFact(_ fact: PersonalFact, handle: ConversationHandle) throws
    -> PersonalFactsSnapshot
  {
    try Task.checkCancellation()
    return try storage().removePersonalFact(fact, handle: handle)
  }
}
