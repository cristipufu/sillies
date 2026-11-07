import Foundation

public struct VaultTextEdit: Sendable {
  public enum Region: Sendable {
    case entireSection
    case blocks(Range<Int>)
  }
  public let location: VaultBlockLocation
  public let expectedRevision: UUID?
  public let text: String
  public let region: Region
  public init(
    location: VaultBlockLocation, expectedRevision: UUID?, text: String,
    region: Region = .entireSection
  ) {
    self.location = location
    self.expectedRevision = expectedRevision
    self.text = text
    self.region = region
  }
}
