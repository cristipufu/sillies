import Foundation
import SilliesCore
import SilliesPersistence

/// Pure state for a loaded range of headers. Query scheduling and selection belong to the UI owner.
package struct VaultListing {
  package private(set) var records: [SessionRecordHeader]
  package private(set) var total: Int
  package private(set) var nextCursor: VaultPageCursor?
  package var hasMore: Bool { records.count < total }

  package init(_ page: VaultPage) {
    records = page.records
    total = page.total
    nextCursor = page.nextCursor
  }

  package mutating func refresh(_ matches: VaultHeaderMatches, changedIDs: Set<UUID>) {
    let existing = Set(records.map(\.id))
    let boundary = hasMore ? nextCursor : nil
    let visible = matches.records.filter { header in
      existing.contains(header.id) || (boundary.map { VaultPageCursor(header) >= $0 } ?? true)
    }
    records = (records.filter { !changedIDs.contains($0.id) } + visible)
      .sorted { VaultPageCursor($0) > VaultPageCursor($1) }
    total = matches.total
  }

  package mutating func append(_ page: VaultPage) {
    let existing = Set(records.map(\.id))
    records += page.records.filter { !existing.contains($0.id) }
    total = page.total
    nextCursor = page.nextCursor
  }

  package mutating func remove(_ id: UUID) {
    guard records.contains(where: { $0.id == id }) else { return }
    records.removeAll { $0.id == id }
    total = max(0, total - 1)
  }
}
