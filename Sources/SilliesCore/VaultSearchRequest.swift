import Foundation

public struct VaultSearchRequest: Sendable {
  public enum Consumer: Sendable { case assistant, workspace }
  public enum Category: String, Codable, CaseIterable, Sendable {
    case all, screenshots, links, meetings, stash
  }
  public static let maximumResults = 5
  public static let maximumQueryCharacters = 200
  private static let minimumRankingCandidates = 20
  public let query: String
  public let category: Category
  public private(set) var limit: Int
  public let consumer: Consumer
  public private(set) var workspaceQuery: VaultWorkspaceQuery?
  public var rankingCandidates: Self {
    var request = self
    request.limit = max(limit, Self.minimumRankingCandidates)
    return request
  }
  public init(workspace query: VaultWorkspaceQuery, limit: Int = 20) {
    self.init(query: query.text, limit: limit, consumer: .workspace)
    workspaceQuery = query
  }
  public init(
    query: String, category: Category = .all, limit: Int = maximumResults,
    consumer: Consumer = .assistant
  ) {
    self.query = String(query.prefix(Self.maximumQueryCharacters)).trimmingCharacters(
      in: .whitespacesAndNewlines)
    self.category = category
    self.consumer = consumer
    self.limit = min(
      consumer == .workspace ? Self.maximumWorkspaceResults : Self.maximumResults, max(1, limit))
  }
  private static let maximumWorkspaceResults = 30
}
