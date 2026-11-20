import Foundation

/// Cached presentation for a passage or an attributed span within it.
struct TranscriptRenderLine: Sendable {
  let time: TimeInterval
  let sequence: Int
  let text: String
  let characterCount: Int

  init(time: TimeInterval, sequence: Int, text: String) {
    self.time = time
    self.sequence = sequence
    self.text = text
    characterCount = text.count
  }

  static func chronologicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.time != rhs.time { return lhs.time < rhs.time }
    return lhs.sequence < rhs.sequence
  }
}
