import Foundation

/// Source captures and authored documents share navigation, without sharing editing ownership.
public struct VaultDocumentMetadata: Codable, Equatable, Sendable {
  public static let maximumTitleScalars = 1_024
  public static let maximumTags = 32
  public static let maximumTagScalars = 80
  public static let maximumCollections = 32
  public enum Kind: String, Codable, Sendable { case capture, note, link }
  public var kind: Kind
  public var title: String
  public var modifiedAt: Date
  public var isStarred: Bool
  public var trashedAt: Date?
  public var tags: [String]
  public var collectionIDs: [UUID]
  public var link: VaultLink?

  public var isValid: Bool {
    title.unicodeScalars.count <= Self.maximumTitleScalars
      && modifiedAt.timeIntervalSince1970.isFinite
      && trashedAt?.timeIntervalSince1970.isFinite != false
      && tags.count <= Self.maximumTags
      && tags.allSatisfy { !$0.isEmpty && $0.unicodeScalars.count <= Self.maximumTagScalars }
      && collectionIDs.count <= Self.maximumCollections
  }

  public init(kind: Kind = .capture, title: String = "", modifiedAt: Date) {
    self.kind = kind
    self.title = title
    self.modifiedAt = modifiedAt
    isStarred = false
    tags = []
    collectionIDs = []
  }
}
