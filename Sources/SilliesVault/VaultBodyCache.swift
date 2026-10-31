import Foundation
import SilliesCore

/// The cost is encoded body bytes. Oversized details are returned to the caller without retention.
struct VaultBodyCache {
  private struct Entry {
    let record: SessionRecord
    let cost: Int
    var access: UInt64
  }
  private let capacity: Int
  private let maximumEntries = 16
  private var entries: [UUID: Entry] = [:]
  private var access: UInt64 = 0
  private(set) var retainedBytes = 0
  init(capacity: Int) { self.capacity = max(0, capacity) }

  mutating func record(_ id: UUID) -> SessionRecord? {
    guard var entry = entries[id] else { return nil }
    access &+= 1
    entry.access = access
    entries[id] = entry
    return entry.record
  }
  mutating func insert(_ record: SessionRecord, cost: Int) {
    remove(record.id)
    guard cost <= capacity else { return }
    while retainedBytes > capacity - cost || entries.count >= maximumEntries {
      guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
      remove(oldest)
    }
    access &+= 1
    entries[record.id] = Entry(record: record, cost: cost, access: access)
    retainedBytes += cost
  }
  mutating func remove(_ id: UUID) {
    if let entry = entries.removeValue(forKey: id) { retainedBytes -= entry.cost }
  }
  mutating func removeAll() {
    entries.removeAll()
    retainedBytes = 0
  }
}
