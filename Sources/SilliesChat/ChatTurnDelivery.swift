import Foundation
import SilliesTTS

/// Presentation delivery owns timing and the prefix confirmed by hardware completion callbacks.
@MainActor final class ChatTurnDelivery {
  struct Snapshot: Sendable {
    var spokenText = ""
    var firstText: Duration?
    var firstAudio: Duration?
  }
  private let started: ContinuousClock.Instant
  private(set) var snapshot = Snapshot()
  init(started: ContinuousClock.Instant) { self.started = started }
  func receivedText() {
    if snapshot.firstText == nil { snapshot.firstText = started.duration(to: .now) }
  }
  func received(_ update: SpeechPlaybackUpdate) {
    switch update {
    case .speaking:
      if snapshot.firstAudio == nil { snapshot.firstAudio = started.duration(to: .now) }
    case .utteranceFinished(let phrase):
      snapshot.spokenText = [snapshot.spokenText, phrase].filter { !$0.isEmpty }.joined(
        separator: " ")
    case .finished, .interrupted: break
    }
  }
}
