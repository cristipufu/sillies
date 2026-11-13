import Foundation
import SilliesCore

/// Native navigation and cached media stay outside the Chat application target.
@MainActor struct ChatVaultPresentation {
  let store: SessionVaultStore
  let openRecord: (UUID) -> Void
  let openPassage: (VaultEvidencePassage, VaultEvidenceAction) -> Void
}

enum VaultEvidenceAction { case read, play }
