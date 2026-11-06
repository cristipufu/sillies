/// One best passage per record, bounded throughout the scan rather than deduplicated afterward.
struct VaultPassageRanking {
  struct Candidate {
    let record: String
    let passage: String
    let score: Float
  }
  private let limit: Int
  private var candidates: [Candidate] = []
  var passages: [String] { candidates.map(\.passage) }
  init(limit: Int) { self.limit = limit }

  mutating func consider(score: Float, identity: () throws -> (String, String)) rethrows {
    guard score > 0 else { return }
    if candidates.count == limit, let last = candidates.last, score < last.score { return }
    let (record, passage) = try identity()
    if let index = candidates.firstIndex(where: { $0.record == record }) {
      guard score > candidates[index].score else { return }
      candidates.remove(at: index)
    }
    let candidate = Candidate(record: record, passage: passage, score: score)
    let insertion =
      candidates.firstIndex { score > $0.score || (score == $0.score && record < $0.record) }
      ?? candidates.count
    guard insertion < limit else { return }
    candidates.insert(candidate, at: insertion)
    if candidates.count > limit { candidates.removeLast() }
  }
}
