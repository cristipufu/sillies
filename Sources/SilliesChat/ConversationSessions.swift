import SilliesCore

/// Bounded by the installed character catalog; retains failed saves after a bubble closes.
@MainActor package final class ConversationSessions {
  private let profiles: [String: CharacterChatProfile]
  private let services: ChatServices
  private var sessions: [String: ChatSession] = [:]
  package init(profiles: [String: CharacterChatProfile], services: ChatServices) {
    self.profiles = profiles
    self.services = services
  }
  package var failedSave: ChatSession? {
    sessions.values.first { $0.history.failure != nil && $0.history.hasUnsavedChanges }
  }
  package func session(for owner: ConversationOwner) -> ChatSession? {
    if let existing = sessions[owner.id] {
      existing.resume()
      return existing
    }
    guard let profile = profiles[owner.id] else { return nil }
    let created = ChatSession(
      companionName: owner.name, profile: profile, services: services, companionID: owner.id)
    sessions[owner.id] = created
    return created
  }
}
