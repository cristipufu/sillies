import Foundation
import SilliesCore
import SilliesPersistence

actor VaultSearchService {
  private let directory: URL
  private var index: VaultSearchIndex?
  private var revision = -1
  init(directory: URL) { self.directory = directory }

  func search(_ request: SessionRecordSearch, records: [SessionRecord], revision: Int) throws
    -> Set<UUID>
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if index == nil { index = try VaultSearchIndex(directory: directory) }
    guard let index else { return [] }
    if revision > self.revision {
      try index.synchronize(records)
      self.revision = revision
    }
    return try index.search(request.query, kind: request.kind)
  }

  func discard() throws {
    index = nil
    revision = -1
    try VaultSearchIndex.erase(directory: directory)
  }
}
