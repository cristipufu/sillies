import Foundation

/// Only changed fields are persisted, so editing a title cannot overwrite concurrent tag changes.
public struct VaultMetadataDraft: Codable, Sendable {
  public let id: UUID
  public let recordID: UUID
  public let title: String?
  public let tags: [String]?

  public init(recordID: UUID, title: String?, tags: [String]?) {
    id = UUID()
    self.recordID = recordID
    self.title = title
    self.tags = tags
  }

  public var isValid: Bool {
    (title?.unicodeScalars.count ?? 0) <= VaultDocumentMetadata.maximumTitleScalars
      && (tags?.count ?? 0) <= VaultDocumentMetadata.maximumTags
      && (tags?.allSatisfy {
        !$0.isEmpty && $0.unicodeScalars.count <= VaultDocumentMetadata.maximumTagScalars
      } ?? true)
  }
}
