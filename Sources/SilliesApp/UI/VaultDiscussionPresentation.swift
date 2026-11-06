import Foundation
import SilliesCore

@MainActor struct VaultDiscussionPresentation {
  let companions: [ConversationOwner]
  let open: (UUID, ConversationOwner) -> SessionFailure?
}
