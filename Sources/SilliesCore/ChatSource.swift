import Foundation

/// A reference supplied by a local tool, never a link invented by a model.
public struct ChatSource: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let title: String
  public let kind: CompanionSkillKind
  public let createdAt: Date
  public private(set) var excerpt: String
  public let links: [URL]
  public let imageFilename: String?
  public func withExcerpt(_ text: String) -> Self {
    var copy = self
    copy.excerpt = text
    return copy
  }
  private let retrievalMethod: VaultSearchMatch.Retrieval?
  public var retrieval: VaultSearchMatch.Retrieval { retrievalMethod ?? .keyword }
  public var audioFilename: String? { nil }

  public init(
    header: SessionRecordHeader, excerpt: String, links: [URL] = [],
    retrieval: VaultSearchMatch.Retrieval = .keyword
  ) {
    self.init(.init(header: header, excerpt: excerpt, retrieval: retrieval), links: links)
  }

  public init(_ match: VaultSearchMatch, links: [URL] = []) {
    id = match.header.id
    title =
      match.documentTitle ?? match.header.windowTitle.flatMap { $0.isEmpty ? nil : $0 }
      ?? match.header.appName
    kind = match.header.kind
    createdAt = match.header.createdAt
    self.excerpt = match.excerpt
    self.links = links
    imageFilename = match.header.imageFilename
    retrievalMethod = match.retrieval
  }
}
extension ChatSource: SessionAttachmentReference {}
