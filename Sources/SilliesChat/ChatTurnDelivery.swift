import Foundation
import SilliesAudio
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
    var endpoint: Duration?
    var recognitionFinalized: Duration?
  }
  private let hostStart: TimeInterval
  private(set) var snapshot = Snapshot()
  init(started: ContinuousClock.Instant, endpoint: VoiceEndpointTiming? = nil) {
    let now = ProcessInfo.processInfo.systemUptime
    let endpoint = endpoint.flatMap { $0.detected <= now ? $0 : nil }
    let elapsed = started.duration(to: .now).components
    let attosecondsPerSecond = 1e18
    let fallbackStart =
      now - Double(elapsed.seconds)
      - Double(elapsed.attoseconds) / attosecondsPerSecond
    hostStart = endpoint?.lastSpeechSample ?? fallbackStart
    if let endpoint {
      snapshot.endpoint = .seconds(endpoint.detected - endpoint.lastSpeechSample)
      snapshot.recognitionFinalized = .seconds(now - hostStart)
    }
  }
  func receivedText() {
    if snapshot.firstText == nil { snapshot.firstText = elapsed }
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
    let elapsed = elapsed
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

  private var elapsed: Duration {
    .seconds(max(0, ProcessInfo.processInfo.systemUptime - hostStart))
  }
}
