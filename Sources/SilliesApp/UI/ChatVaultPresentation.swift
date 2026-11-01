import Foundation

/// Native navigation and cached media stay outside the Chat application target.
@MainActor struct ChatVaultPresentation {
  let store: SessionVaultStore
  let openRecord: (UUID) -> Void
}
