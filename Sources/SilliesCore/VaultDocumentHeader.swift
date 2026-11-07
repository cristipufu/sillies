import Foundation

/// A complete header, not a SessionRecord with omitted source text.
public struct VaultDocumentHeader: Identifiable, Equatable, Sendable {
  public let source: SessionRecordHeader
  public let metadata: VaultDocumentMetadata
  public let excerpt: String
  public let match: VaultBlockLocation?
  public private(set) var matchSeconds: Double?
  public func timed(at seconds: Double?) -> Self {
    var copy = self
    copy.matchSeconds = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    return copy
  }
  public var id: UUID { source.id }
  public var title: String { metadata.title.isEmpty ? source.displayTitle : metadata.title }

  public init(
    source: SessionRecordHeader, metadata: VaultDocumentMetadata,
    excerpt: String = "", match: VaultBlockLocation? = nil
  ) {
    self.source = source
    self.metadata = metadata
    self.excerpt = excerpt
    self.match = match
  }
}
