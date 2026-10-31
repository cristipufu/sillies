import Foundation

/// Bounded invalidations, not record bodies. Overflow requests a fresh listing instead of losing changes.
package struct VaultChangeJournal {
  package enum Changes {
    case reload
    case records(Set<UUID>)
  }
  private struct Entry {
    let version: Int
    let ids: Set<UUID>
  }
  private static let capacity = 256
  private static let maximumIDsPerEntry = 256
  private var entries: [Entry] = []
  private var floor = 0
  package private(set) var version = 0

  package init() {}
  package mutating func record(_ ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    guard ids.count <= Self.maximumIDsPerEntry else {
      reset()
      return
    }
    version += 1
    entries.append(Entry(version: version, ids: ids))
    if entries.count > Self.capacity { floor = entries.removeFirst().version }
  }
  package mutating func reset() {
    version += 1
    floor = version
    entries.removeAll()
  }
  package func revision(for id: UUID?) -> Int {
    guard let id else { return floor }
    return entries.last { $0.ids.contains(id) }?.version ?? floor
  }
  package func changes(since preceding: Int) -> Changes {
    guard preceding >= floor else { return .reload }
    return .records(
      entries.lazy.filter { $0.version > preceding }.reduce(into: Set<UUID>()) {
        $0.formUnion($1.ids)
      })
  }
}
