import Foundation
import SilliesCore

@MainActor struct VaultDiscussionPresentation {
  private let availableCompanions: () -> [ConversationOwner]
  var companions: [ConversationOwner] { availableCompanions() }
  let open: (UUID, ConversationOwner) -> SessionFailure?

  init(
    companions: [ConversationOwner], open: @escaping (UUID, ConversationOwner) -> SessionFailure?
  ) {
    self.init(availableCompanions: { companions }, open: open)
  }
  init(
    availableCompanions: @escaping () -> [ConversationOwner],
    open: @escaping (UUID, ConversationOwner) -> SessionFailure?
  ) {
    self.availableCompanions = availableCompanions
    self.open = open
  }
}
