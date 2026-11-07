import Foundation

/// Reciprocal-rank fusion combines independent rankings without comparing incompatible raw scores.
public enum VaultRankFusion {
  private static let rankConstant = 60.0
  public static func merge<Element, Identity: Hashable>(
    _ rankings: [[Element]], identifiedBy identity: KeyPath<Element, Identity>, limit: Int
  ) -> [Element] {
    guard limit > 0 else { return [] }
    var scores: [Identity: Double] = [:]
    var order: [Identity: Int] = [:]
    var elements: [Identity: Element] = [:]
    for ranking in rankings {
      var seen: Set<Identity> = []
      for (rank, element) in ranking.enumerated() {
        let id = element[keyPath: identity]
        guard seen.insert(id).inserted else { continue }
        if elements[id] == nil {
          order[id] = order.count
          elements[id] = element
        }
        scores[id, default: 0] += 1 / (rankConstant + Double(rank + 1))
      }
    }
    return scores.keys.sorted {
      let lhs = scores[$0, default: 0]
      let rhs = scores[$1, default: 0]
      return lhs == rhs ? order[$0, default: 0] < order[$1, default: 0] : lhs > rhs
    }.prefix(limit).compactMap { elements[$0] }
  }
}
