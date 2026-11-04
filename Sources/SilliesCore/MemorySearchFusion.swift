import Foundation

/// Preserve the strongest keyword match, then alternate independent retrieval rankings.
public enum MemorySearchFusion {
  public static func merge(keywords: [CompanionMemory], semantic: [CompanionMemory], limit: Int)
    -> [CompanionMemory]
  {
    var result: [CompanionMemory] = []
    var seen = Set<UUID>()
    for index in 0..<max(keywords.count, semantic.count) {
      for list in [keywords, semantic] where index < list.count {
        if seen.insert(list[index].id).inserted { result.append(list[index]) }
        if result.count >= max(1, limit) { return result }
      }
    }
    return result
  }
}
