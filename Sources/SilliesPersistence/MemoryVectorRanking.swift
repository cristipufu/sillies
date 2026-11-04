/// Retain only the best identities, with deterministic ties independent of SQLite's scan order.
struct MemoryVectorRanking {
  private let limit: Int
  private var matches: [(id: String, score: Float)] = []
  var identities: [String] { matches.map(\.id) }

  init(limit: Int) { self.limit = limit }

  mutating func consider(score: Float, identity: () throws -> String) rethrows {
    if matches.count == limit, let lowest = matches.last, score < lowest.score { return }
    // Most rows never enter the result set; do not allocate their identities.
    let id = try identity()
    let position =
      matches.firstIndex {
        score > $0.score || (score == $0.score && id < $0.id)
      } ?? matches.count
    guard position < limit else { return }
    matches.insert((id, score), at: position)
    if matches.count > limit { matches.removeLast() }
  }
}
