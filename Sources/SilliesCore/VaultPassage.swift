import Foundation

/// One bounded, revision-owned excerpt. Offsets use SQLite's Unicode scalar indexing.
public struct VaultPassage: Sendable {
  public static let maximumScalars = 1_200
  public static let overlapScalars = 160
  public let recordID: UUID
  public let blockID: Int64
  public let revision: String
  public let offset: Int
  public let text: String
  public let isLast: Bool

  public init(
    recordID: UUID, revision: String, offset: Int, text: String, isLast: Bool, blockID: Int64 = 0
  ) {
    self.recordID = recordID
    self.blockID = blockID
    self.revision = revision
    self.offset = offset
    self.text = text
    self.isLast = isLast
  }

  public var nextOffset: Int? {
    guard offset >= 0, text.unicodeScalars.count <= Self.maximumScalars else { return nil }
    let (next, overflow) = offset.addingReportingOverflow(
      max(1, text.unicodeScalars.count - Self.overlapScalars))
    return overflow ? nil : next
  }
}
