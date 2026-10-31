import Foundation
import SilliesCore

/// Stable chronological position: new records do not shift the next page's starting point.
public struct VaultPageCursor: Sendable, Equatable, Comparable {
  public let createdAt: Date
  public let id: UUID
  public init(_ header: SessionRecordHeader) {
    createdAt = header.createdAt
    id = header.id
  }
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

public struct VaultHeaderMatches: Sendable {
  public let records: [SessionRecordHeader]
  public let total: Int
  public init(records: [SessionRecordHeader], total: Int) {
    self.records = records
    self.total = total
  }
}
