import Foundation
import SilliesCore

/// Encoded bytes plus potentially overlaid text bound retention conservatively. This is not process RSS.
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
    guard cost >= 0, cost <= capacity else { return }
    var retainedCost = cost
    for text in [record.transcript, record.extractedText] + record.stashedItems {
      guard text.utf8.count <= capacity - retainedCost else { return }
      retainedCost += text.utf8.count
    }
    while retainedBytes > capacity - retainedCost || entries.count >= maximumEntries {
      guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
      remove(oldest)
    }
    access &+= 1
    entries[record.id] = Entry(record: record, cost: retainedCost, access: access)
    retainedBytes += retainedCost
  }
  mutating func remove(_ id: UUID) {
    if let entry = entries.removeValue(forKey: id) { retainedBytes -= entry.cost }
  }
  mutating func removeAll() {
    entries.removeAll()
    retainedBytes = 0
  }
}
