import Foundation
import SilliesCore

/// Group only a loaded, chronologically ordered page; relevance order is left intact.
struct VaultDateGroup: Identifiable {
  let id: Date
  let title: String
  var records: [VaultDocumentHeader]
  static func make(
    _ records: [VaultDocumentHeader], ordering: VaultWorkspaceQuery.Ordering, now: Date = Date()
  ) -> [Self] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
    var groups: [Self] = []
    for record in records {
      let date = ordering == .modified ? record.metadata.modifiedAt : record.source.createdAt
      let day = calendar.startOfDay(for: date)
      let title: String
      let id: Date
      if day == today {
        title = String(localized: "Today")
        id = day
      } else if day == yesterday {
        title = String(localized: "Yesterday")
        id = day
      } else {
        title = date.formatted(.dateTime.month(.wide).year())
        id = calendar.dateInterval(of: .month, for: date)?.start ?? day
      }
      if groups.last?.id == id {
        groups[groups.count - 1].records.append(record)
      } else {
        groups.append(.init(id: id, title: title, records: [record]))
      }
    }
    return groups
  }
}
