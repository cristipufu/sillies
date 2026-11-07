import Foundation

/// A recoverable edit retains its original revision and exact loaded range.
public struct VaultDraft: Codable, Equatable, Sendable {
  public let id: UUID
  public let location: VaultBlockLocation
  public let expectedRevision: UUID?
  public let blockRange: Range<Int>
  public let text: String

  public init(location: VaultBlockLocation, revision: UUID?, range: Range<Int>, text: String) {
    id = UUID()
    self.location = location
    expectedRevision = revision
    blockRange = range
    self.text = text
  }

  public var edit: VaultTextEdit {
    .init(
      location: location, expectedRevision: expectedRevision, text: text,
      region: .blocks(blockRange))
  }
  public var isValid: Bool {
    location.ordinal >= 0 && location.ordinal <= Int.max - VaultTextBlocks.maximumEditableBlocks
      && blockRange.lowerBound >= 0 && blockRange.count <= VaultTextBlocks.maximumEditableBlocks
      && text.unicodeScalars.count <= VaultTextBlocks.maximumEditableScalars
  }
}
