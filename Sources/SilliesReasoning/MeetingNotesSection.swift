/// Both notes modes use the same plain native-reader layout.
struct MeetingNotesSection: Sendable {
  let title: String
  let passages: [String]
  var text: String { title + "\n" + passages.map { "• " + $0 }.joined(separator: "\n") }
}
