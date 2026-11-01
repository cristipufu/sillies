import Foundation

public struct VaultSearchMatch: Sendable {
  public let header: SessionRecordHeader
  public let excerpt: String
  public init(header: SessionRecordHeader, excerpt: String) {
    self.header = header
    self.excerpt = excerpt
  }
}
