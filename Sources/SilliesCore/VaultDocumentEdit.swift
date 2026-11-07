import Foundation

/// Edits describe user intent; persistence applies them to current state inside a transaction.
public enum VaultDocumentEdit: Sendable {
  case rename(String)
  case star, unstar
  case moveToTrash, restore
  case tags([String])
  case collections([UUID])
  case addToCollection(UUID)
  case removeFromCollection(UUID)
  case linkPreview(VaultLink)
}
