import Foundation
import SilliesCore
import SilliesDiagnostics

/// Reports state and timing only. This adapter never receives message contents.
@MainActor final class ChatDiagnostics {
  private let sink: DiagnosticSink
  private let session = UUID()
  private var phase: ChatSession.Phase?
  private var measuredTurn: UUID?
  private var reported: Set<DiagnosticEvent.Metric> = []
  private var acousticTurn: (utterance: UUID, turn: UUID)?

  init(sink: DiagnosticSink) { self.sink = sink }

  func record(_ action: DiagnosticEvent.Action, turn: UUID, reason: DiagnosticEvent.Reason? = nil) {
    var event = DiagnosticEvent(.chat, action, operation: turn)
    event.relatedOperation = session
    event.reason = reason
    sink.record(event)
  }

  func failed(_ error: any Error, area: DiagnosticEvent.Area, turn: UUID) {
    var event = DiagnosticEvent(area, .failed, operation: turn).failing(error)
    event.relatedOperation = session
    if let failure = error as? SessionFailure {
      event.fault = DiagnosticEvent.Fault(rawValue: failure.category.rawValue) ?? .unknown
    }
    sink.record(event)
  }

  func speechAttempt(_ attempt: UUID, for turn: UUID) {
    var event = DiagnosticEvent(.synthesis, .started, operation: attempt)
    event.relatedOperation = turn
    sink.record(event)
  }

  func acoustics(_ evidence: VoiceAcousticEvidence, utterance: UUID, turn: UUID) {
    if evidence.boundary == .onset { acousticTurn = (utterance, turn) }
    let originalTurn = acousticTurn?.utterance == utterance ? acousticTurn?.turn ?? turn : turn
    if evidence.boundary == .endpoint, acousticTurn?.utterance == utterance { acousticTurn = nil }
    var values = DiagnosticAcoustics(
      boundary: evidence.boundary == .onset ? .onset : .endpoint, utterance: utterance)
    values.samples = evidence.window.samples
    values.referenceSamples = evidence.window.referenceSamples
    values.clippedSamples = evidence.window.clippedSamples
    values.referenceDecibels = evidence.window.referenceDecibels
    values.microphoneDecibels = evidence.window.microphoneDecibels
    values.cleanedDecibels = evidence.window.cleanedDecibels
    values.droppedReferenceFrames = evidence.delivery.droppedReferenceFrames
    values.rejectedReferenceFrames = evidence.delivery.rejectedReferenceFrames
    values.staleReferenceFrames = evidence.delivery.staleReferenceFrames
    values.referenceDiscontinuities = evidence.delivery.referenceDiscontinuities
    values.microphoneDiscontinuities = evidence.delivery.microphoneDiscontinuities
    values.referenceAgeMilliseconds = evidence.delivery.referenceAgeMilliseconds
    values.echoDelayMilliseconds = evidence.echo.delayMilliseconds
    values.echoReturnLossDecibels = evidence.echo.returnLossDecibels
    values.echoReductionDecibels = evidence.echo.reductionDecibels
    var event = DiagnosticEvent(.capture, .acousticAssessment, operation: originalTurn)
    event.relatedOperation = session
    event.phase = phase.flatMap { DiagnosticEvent.Phase(rawValue: $0.rawValue) }
    event.acoustics = values
    sink.record(event)
  }

  func phaseChanged(_ value: ChatSession.Phase, turn: UUID) {
    guard phase != value else { return }
    phase = value
    var event = DiagnosticEvent(.chat, .phaseChanged, operation: turn)
    event.phase = DiagnosticEvent.Phase(rawValue: value.rawValue)
    event.relatedOperation = session
    sink.record(event)
  }

  func modeChanged(_ mode: ConversationMode) {
    var event = DiagnosticEvent(.chat, .phaseChanged, operation: session)
    event.phase = mode == .talk ? .talk : .chat
    sink.record(event)
  }

  func delivery(_ snapshot: ChatTurnDelivery.Snapshot?, turn: UUID) {
    guard let snapshot else { return }
    if measuredTurn != turn {
      measuredTurn = turn
      reported.removeAll(keepingCapacity: true)
    }
    let measurements: [(DiagnosticEvent.Metric, Duration?)] = [
      (.firstText, snapshot.firstText), (.firstPCM, snapshot.firstPCM),
      (.firstAudio, snapshot.firstAudio), (.endpoint, snapshot.endpoint),
      (.recognitionFinalized, snapshot.recognitionFinalized),
      (.voicePrepared, snapshot.voicePrepared),
    ]
    for (metric, value) in measurements {
      guard let value, reported.insert(metric).inserted else { continue }
      var event = DiagnosticEvent(.chat, .milestone, operation: turn)
      event.metric = metric
      let duration = value.components
      event.milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
      event.relatedOperation = session
      sink.record(event)
    }
  }

  func contextPrepared(_ inspection: ReplyContextInspection?, toolCalls: Int, turn: UUID) {
    guard let inspection else { return }
    let counts: [(DiagnosticEvent.Metric, Int)] = [
      (.contextMessages, inspection.recentMessages),
      (.contextToolResults, inspection.previousToolResults), (.replyToolCalls, toolCalls),
    ]
    for (metric, count) in counts {
      var event = DiagnosticEvent(.chat, .contextPrepared, operation: turn)
      event.metric = metric
      event.count = count
      event.relatedOperation = session
      sink.record(event)
    }
  }
}
