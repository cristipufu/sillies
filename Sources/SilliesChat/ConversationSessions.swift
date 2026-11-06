import SilliesCore

/// Bounded by the installed character catalog; retains failed saves after a bubble closes.
@MainActor package final class ConversationSessions {
  private let profile: (String) -> CharacterChatProfile?
  private let services: (ConversationOwner) -> ChatServices
  private let languageOverride: (String) -> String?
  private var sessions: [String: ChatSession] = [:]
  package init(profiles: [String: CharacterChatProfile], services: ChatServices) {
    self.profile = { profiles[$0] }
    self.services = { _ in services }
    languageOverride = { _ in nil }
  }
  package init(
    profile: @escaping (String) -> CharacterChatProfile?,
    services: @escaping (ConversationOwner) -> ChatServices,
    languageOverride: @escaping (String) -> String? = { _ in nil }
  ) {
    self.profile = profile
    self.services = services
    self.languageOverride = languageOverride
  }
  package var failedSave: ChatSession? {
    sessions.values.first { $0.history.failure != nil && $0.history.hasUnsavedChanges }
  }
  package func refreshProfile(for id: String) {
    guard let session = sessions[id], let profile = profile(id) else { return }
    session.updateProfile(profile, languageOverride: languageOverride(id))
  }
  package func session(for owner: ConversationOwner) -> ChatSession? {
    if let existing = sessions[owner.id] {
      existing.resume()
      if let profile = profile(owner.id) {
        existing.updateProfile(profile, languageOverride: languageOverride(owner.id))
      }
      return existing
    }
    guard let profile = profile(owner.id) else { return nil }
    let created = ChatSession(
      companionName: owner.name, profile: profile, services: services(owner), companionID: owner.id,
      languageOverride: languageOverride(owner.id))
    sessions[owner.id] = created
    return created
  }
}
