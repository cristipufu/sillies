import Foundation
import SilliesAudio
import SilliesCore
import SilliesTTS
import Synchronization

/// Confirm playback before asynchronous UI delivery; old attempts cannot advance a resumed reply.
final class ChatTurnDelivery: Sendable {
  struct Snapshot: Sendable {
    var speech = SpokenReplyProgress()
    var spokenText: String { speech.completedText }
    var firstText: Duration?
    var firstAudio: Duration?
    var phraseReady: Duration?
    var preparationStarted: Duration?
    var voicePrepared: Duration?
    var firstPCM: Duration?
    var endpoint: Duration?
    var recognitionFinalized: Duration?
  }
  private struct State {
    var snapshot: Snapshot
    var speechID: UUID?
  }
  private let hostStart: TimeInterval
  private let state: Mutex<State>
  var snapshot: Snapshot { state.withLock { $0.snapshot } }

  init(
    started: ContinuousClock.Instant, endpoint: VoiceEndpointTiming? = nil,
    speech: SpokenReplyProgress = .init()
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    let endpoint = endpoint.flatMap { $0.detected <= now ? $0 : nil }
    let elapsed = started.duration(to: .now).components
    let attosecondsPerSecond = 1e18
    let fallbackStart =
      now - Double(elapsed.seconds) - Double(elapsed.attoseconds) / attosecondsPerSecond
    hostStart = endpoint?.lastSpeechSample ?? fallbackStart
    var snapshot = Snapshot()
    snapshot.speech = speech
    if let endpoint {
      snapshot.endpoint = .seconds(endpoint.detected - endpoint.lastSpeechSample)
      snapshot.recognitionFinalized = .seconds(now - hostStart)
    }
    state = Mutex(State(snapshot: snapshot))
  }

  func beginSpeech(_ id: UUID) { state.withLock { $0.speechID = id } }
  func endSpeech(_ id: UUID) {
    state.withLock { if $0.speechID == id { $0.speechID = nil } }
  }
  func plannedSpeech(_ phrase: String) { state.withLock { $0.snapshot.speech.append(phrase) } }
  func receivedText() {
    state.withLock { if $0.snapshot.firstText == nil { $0.snapshot.firstText = elapsed } }
  }
  @discardableResult func received(_ update: SpeechPlaybackUpdate, from id: UUID) -> Bool {
    state.withLock { state in
      guard state.speechID == id else { return false }
      switch update {
      case .milestone(let milestone): record(milestone, in: &state.snapshot)
      case .utteranceFinished(let phrase): state.snapshot.speech.completed(phrase)
      case .speaking, .finished, .interrupted, .attribution: break
      }
      return true
    }
  }

  private func record(_ milestone: SpeechDeliveryMilestone, in snapshot: inout Snapshot) {
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
