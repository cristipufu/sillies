import Foundation

/// User words become literal FTS terms; model-produced query syntax is never executed as SQL/FTS.
enum VaultSearchTerms {
  enum Matching { case allTerms, anyTerm }
  private static let maximumTokens = 32
  static func expression(_ query: String, matching: Matching = .allTerms) -> String? {
    let tokens = query.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.prefix(maximumTokens)
    guard !tokens.isEmpty else { return nil }
    return tokens.map { "\"\($0)\"*" }.joined(separator: matching == .allTerms ? " AND " : " OR ")
  }
}
