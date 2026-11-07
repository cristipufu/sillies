import Foundation

/// Source identities remain separate from the document's editable title and tags.
public struct VaultSourceFilter: Codable, Hashable, Sendable {
  public static let maximumIdentifierScalars = 1_024
  public var appName: String?
  public var companionID: String?
  public var languageIdentifier: String?
  public init(appName: String? = nil, companionID: String? = nil, languageIdentifier: String? = nil)
  {
    self.appName = appName
    self.companionID = companionID
    self.languageIdentifier = languageIdentifier
  }
  public var isEmpty: Bool { appName == nil && companionID == nil && languageIdentifier == nil }
  public var isValid: Bool {
    [appName, companionID, languageIdentifier].compactMap { $0 }.allSatisfy {
      !$0.isEmpty && $0.unicodeScalars.count <= Self.maximumIdentifierScalars
    }
  }
  public func includes(_ header: SessionRecordHeader) -> Bool {
    (appName == nil || appName == header.appName)
      && (companionID == nil || companionID == header.characterID)
      && (languageIdentifier == nil || languageIdentifier == header.languageIdentifier)
  }
}
