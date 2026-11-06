import Foundation

public struct VaultSearchMatch: Sendable {
  public enum Retrieval: String, Codable, Sendable { case keyword, semantic }
  public let header: SessionRecordHeader
  public let excerpt: String
  public let retrieval: Retrieval
  public init(header: SessionRecordHeader, excerpt: String, retrieval: Retrieval = .keyword) {
    self.header = header
    self.excerpt = excerpt
    self.retrieval = retrieval
  }
}
