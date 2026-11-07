import Foundation

public struct VaultSourceFacet: Identifiable, Sendable {
  public enum Kind: String, Sendable { case app, companion, language }
  public static let maximumChoices = 100
  public let id: String
  public let title: String
  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}
