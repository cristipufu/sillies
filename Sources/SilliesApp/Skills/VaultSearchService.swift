import Foundation
import SilliesCore
import SilliesPersistence

actor VaultSearchService {
  struct Snapshot: Sendable {
    let records: [SessionRecord]
    let versions: [UUID: Int]
    let revision: Int
  }
  private let directory: URL
  private var index: VaultSearchIndex?
  private var revision = -1
  private var versions: [UUID: Int] = [:]
  var indexedDocumentCount: Int { index?.indexedDocumentCount ?? 0 }
  init(directory: URL) { self.directory = directory }

  func search(_ request: SessionRecordSearch, snapshot: Snapshot) throws
    -> Set<UUID>
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if index == nil { index = try VaultSearchIndex(directory: directory) }
    guard let index else { return [] }
    if snapshot.revision > self.revision {
      let changed = snapshot.records.filter { self.versions[$0.id] != snapshot.versions[$0.id] }
      let removed = Set(self.versions.keys).subtracting(snapshot.versions.keys)
      try index.apply(upserting: changed, removing: removed)
      self.versions = snapshot.versions
      self.revision = snapshot.revision
    }
    return try index.search(request.query, kind: request.kind)
  }

  func remove(_ ids: Set<UUID>, at revision: Int) throws {
    guard revision >= self.revision else { return }
    if index == nil { index = try VaultSearchIndex(directory: directory) }
    try index?.apply(upserting: [], removing: ids)
    for id in ids { versions.removeValue(forKey: id) }
    // Deletions must not cause a stale search snapshot to resurrect removed text.
    // Other dirty records still synchronize when the current snapshot is searched.
    self.revision = revision - 1
  }
}
