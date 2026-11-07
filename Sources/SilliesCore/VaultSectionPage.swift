import Foundation

public struct VaultSectionPage: Sendable {
  public static let maximumBlocks = 16
  public let blocks: [VaultContentBlock]
  public let nextOrdinal: Int?
  public let previousOrdinal: Int?
  public init(blocks: [VaultContentBlock], nextOrdinal: Int?, previousOrdinal: Int?) {
    self.blocks = blocks
    self.nextOrdinal = nextOrdinal
    self.previousOrdinal = previousOrdinal
  }
}
