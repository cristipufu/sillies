import Foundation
import SilliesTTS

/// Presentation delivery owns timing and the prefix confirmed by hardware completion callbacks.
@MainActor final class ChatTurnDelivery {
  struct Snapshot: Sendable {
    var spokenText = ""
    var firstText: Duration?
    var firstAudio: Duration?
    var phraseReady: Duration?
    var preparationStarted: Duration?
    var voicePrepared: Duration?
    var firstPCM: Duration?
  }
  private let started: ContinuousClock.Instant
  private let hostStart: TimeInterval
  private(set) var snapshot = Snapshot()
  init(started: ContinuousClock.Instant) {
    self.started = started
    let elapsed = started.duration(to: .now).components
    let attosecondsPerSecond = 1e18
    hostStart =
      ProcessInfo.processInfo.systemUptime - Double(elapsed.seconds)
      - Double(elapsed.attoseconds) / attosecondsPerSecond
  }
  func receivedText() {
    if snapshot.firstText == nil { snapshot.firstText = started.duration(to: .now) }
  }
  func received(_ update: SpeechPlaybackUpdate) {
    switch update {
    case .milestone(let milestone): record(milestone)
    case .utteranceFinished(let phrase):
      snapshot.spokenText = [snapshot.spokenText, phrase].filter { !$0.isEmpty }.joined(
        separator: " ")
    case .speaking, .finished, .interrupted: break
    }
  }

  private func record(_ milestone: SpeechDeliveryMilestone) {
    let elapsed = started.duration(to: .now)
    switch milestone {
    case .phraseReady: if snapshot.phraseReady == nil { snapshot.phraseReady = elapsed }
    case .preparationStarted:
      if snapshot.preparationStarted == nil { snapshot.preparationStarted = elapsed }
    case .voicePrepared: if snapshot.voicePrepared == nil { snapshot.voicePrepared = elapsed }
    case .firstPCM: if snapshot.firstPCM == nil { snapshot.firstPCM = elapsed }
    case .audibleOutput(let time):
      if snapshot.firstAudio == nil, time.isFinite, time >= hostStart {
        snapshot.firstAudio = .seconds(time - hostStart)
      }
    }
  }
}
