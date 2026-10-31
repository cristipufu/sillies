import Foundation

public enum VaultRetentionPolicy: String, Codable, CaseIterable, Sendable {
  case keepAll, recent200, recent500, recent1000
  public var limit: Int? {
    switch self {
    case .keepAll: nil
    case .recent200: 200
    case .recent500: 500
    case .recent1000: 1_000
    }
  }
  public var title: String {
    limit.map { "Keep latest \($0) unprotected captures" } ?? "Keep everything until I delete it"
  }
  public func expired(in records: [SessionRecord]) -> [SessionRecord] {
    guard let limit else { return [] }
    let eligible = records.filter { $0.kind != .stash && !$0.isProtected }
      .sorted { $0.createdAt > $1.createdAt }
    return Array(eligible.dropFirst(limit))
  }
}
