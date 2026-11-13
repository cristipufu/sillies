import Foundation
import SilliesCore

/// A speaking tile needs a consistent human identity, not a clock, room code or chat status.
struct MeetParticipantMetadata {
  let participant: CallParticipantLabel
  init?(texts: [String]) {
    guard !texts.isEmpty,
      texts.allSatisfy({
        $0.utf8.count <= CallSpeakerName.maximumUTF8Bytes
          && $0.count <= CallSpeakerName.maximumCharacters
      })
    else { return nil }
    let people = texts.compactMap(CallParticipantLabel.init)
    guard people.count == texts.count, let first = people.first,
      people.allSatisfy({ $0.name.comparisonKey == first.name.comparisonKey }),
      Self.isPerson(first.name)
    else { return nil }
    participant = people.first(where: { $0.identity == .local }) ?? first
  }
  private static func isPerson(_ name: CallSpeakerName) -> Bool {
    let value = name.comparisonKey
    guard value.unicodeScalars.contains(where: CharacterSet.letters.contains),
      value != "am", value != "pm", !isClock(value), !isRoomCode(value)
    else { return false }
    let words = value.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }.joined(separator: " ")
    return !(" " + words + " ").contains(" says in chat ")
  }
  private static func isRoomCode(_ value: String) -> Bool {
    let segments = value.split(separator: "-", omittingEmptySubsequences: false)
    return segments.map(\.count) == [3, 4, 3]
      && segments.allSatisfy { $0.utf8.allSatisfy { (97...122).contains($0) } }
  }
  private static func isClock(_ value: String) -> Bool {
    var time = value
    for period in ["am", "pm"] {
      if time.hasSuffix(period) { time = String(time.dropLast(period.count)) }
    }
    let fields = time.trimmingCharacters(in: .whitespaces)
      .split(whereSeparator: { $0 == ":" || $0 == "." })
    guard fields.count == 2, let hour = fields.first, let minute = fields.last,
      (1...2).contains(hour.count), minute.count == 2
    else { return false }
    return hour.allSatisfy(\.isNumber) && minute.allSatisfy(\.isNumber)
  }
}
