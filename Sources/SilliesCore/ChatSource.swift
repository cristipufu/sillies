import Foundation

/// A reference supplied by a local tool, never a link invented by a model.
public struct ChatSource: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let title: String
  public let kind: CompanionSkillKind
  public let createdAt: Date
  public let excerpt: String
  public let links: [URL]
  public let imageFilename: String?
  private let retrievalMethod: VaultSearchMatch.Retrieval?
  public var retrieval: VaultSearchMatch.Retrieval { retrievalMethod ?? .keyword }
  public var audioFilename: String? { nil }

  public init(
    header: SessionRecordHeader, excerpt: String, links: [URL] = [],
    retrieval: VaultSearchMatch.Retrieval = .keyword
  ) {
    id = header.id
    title = header.windowTitle.flatMap { $0.isEmpty ? nil : $0 } ?? header.appName
    kind = header.kind
    createdAt = header.createdAt
    self.excerpt = excerpt
    self.links = links
    imageFilename = header.imageFilename
    retrievalMethod = retrieval
  }
}
extension ChatSource: SessionAttachmentReference {}
