/// A roster is complete only when every row can be read and its membership stays unchanged.
struct CallSpeakerRosterRead<Row: Equatable> {
  let readRows: () -> [Row]?
  let readName: (Row) -> String?

  func read() -> CallSpeakerRoster? {
    guard let rows = readRows(), !rows.isEmpty,
      rows.count <= CallSpeakerAX.maximumChildren
    else { return nil }
    var names: [String] = []
    for row in rows {
      guard let name = readName(row) else { return nil }
      names.append(name)
    }
    guard readRows() == rows else { return nil }
    return .init(rows: names, declaredCount: rows.count)
  }
}
