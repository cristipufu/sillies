import Foundation

/// A record ID already establishes document identity. Rank requested details before title matches.
struct VaultPassageQuery {
  private static let maximumTerms = 32
  let details: Set<String>
  let all: Set<String>

  init(query: String, title: String) {
    all = Set(Self.words(query).prefix(Self.maximumTerms))
    let detailTerms = all.subtracting(Self.words(title))
    details = detailTerms.isEmpty ? all : detailTerms
  }

  struct Score: Comparable {
    let details: Int
    let total: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.details == rhs.details ? lhs.total < rhs.total : lhs.details < rhs.details
    }
  }

  func score(_ text: String) -> Score {
    let words = Set(Self.words(text))
    return .init(details: details.intersection(words).count, total: all.intersection(words).count)
  }

  func missingDetails(in texts: [String]) -> Set<String> {
    details.subtracting(texts.flatMap(Self.words))
  }

  private static func words(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }
      .map(String.init)
  }
}
