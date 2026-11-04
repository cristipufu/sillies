import Foundation
import SilliesTextModels

/// Monotonic generation milestones and exact streamed-text validation for the contention probe.
actor VoiceOverlapTiming {
  private let started: TimeInterval
  private(set) var first: TimeInterval?
  private(set) var completed: TimeInterval?
  private(set) var voiceStarted: TimeInterval?
  private(set) var text = ""
  init(started: TimeInterval) { self.started = started }
  func received(_ delta: String) -> Bool {
    guard !delta.isEmpty else { return false }
    let isFirst = first == nil
    if isFirst { first = ProcessInfo.processInfo.systemUptime - started }
    text += delta
    return isFirst
  }
  func finished(_ expected: String) throws {
    guard !text.isEmpty,
      text.trimmingCharacters(in: .whitespacesAndNewlines)
        == expected.trimmingCharacters(in: .whitespacesAndNewlines)
    else { throw TextModelError.invalidResponse }
    completed = ProcessInfo.processInfo.systemUptime - started
  }
  func synthesisRequested() { voiceStarted = ProcessInfo.processInfo.systemUptime - started }
}
