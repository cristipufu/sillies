import Foundation

public struct VaultSearchRequest: Sendable {
  public enum Category: String, Codable, CaseIterable, Sendable {
    case all, screenshots, links, meetings, stash
  }
  public static let maximumResults = 5
  public static let maximumQueryCharacters = 200
  public let query: String
  public let category: Category
  public let limit: Int
  public init(query: String, category: Category = .all, limit: Int = maximumResults) {
    self.query = String(query.prefix(Self.maximumQueryCharacters)).trimmingCharacters(
      in: .whitespacesAndNewlines)
    self.category = category
    self.limit = min(Self.maximumResults, max(1, limit))
  }
}
