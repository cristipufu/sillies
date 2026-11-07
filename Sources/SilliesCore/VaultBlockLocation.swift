import Foundation

public struct VaultBlockLocation: Codable, Hashable, Sendable {
  public let recordID: UUID
  public let section: VaultDocumentSection
  public let ordinal: Int
  public init(recordID: UUID, section: VaultDocumentSection, ordinal: Int = 0) {
    self.recordID = recordID
    self.section = section
    self.ordinal = max(0, ordinal)
  }
}
