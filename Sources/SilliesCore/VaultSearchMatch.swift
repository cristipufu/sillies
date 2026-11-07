import Foundation

public struct VaultSearchMatch: Sendable {
  public enum Retrieval: String, Codable, Sendable { case keyword, semantic }
  public let header: SessionRecordHeader
  public let excerpt: String
  public let retrieval: Retrieval
  public private(set) var documentTitle: String?
  public private(set) var location: VaultBlockLocation?
  public init(header: SessionRecordHeader, excerpt: String, retrieval: Retrieval = .keyword) {
    self.header = header
    self.excerpt = excerpt
    self.retrieval = retrieval
  }
  public func located(in document: VaultDocumentHeader, at location: VaultBlockLocation? = nil)
    -> Self
  {
    var copy = self
    copy.documentTitle = document.title
    copy.location = location ?? document.match
    return copy
  }
}
