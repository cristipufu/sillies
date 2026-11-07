import Foundation

/// The acknowledged edit and its current source identities travel together to the editor.
public struct VaultDraftCommit: Sendable {
  public let revision: UUID
  public let blocks: [VaultContentBlock]
  public init(revision: UUID, blocks: [VaultContentBlock]) {
    self.revision = revision
    self.blocks = blocks
  }
}
