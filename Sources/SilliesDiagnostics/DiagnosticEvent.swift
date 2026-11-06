import Foundation

/// Deliberately has no message, prompt, transcript, path, URL or arbitrary metadata field.
package struct DiagnosticEvent: Codable, Sendable, Equatable {
  package enum Area: String, Codable, Sendable {
    case app, chat, recognition, synthesis, inference, diagnostics
  }
  package enum Action: String, Codable, Sendable {
    case started, completed, failed, cancelled, preempted, phaseChanged, speechDetected
    case speechEnded, emptyRecognition, recoveryStarted, playbackInterrupted, modelSelected
    case milestone, eventsDropped, contextPrepared
  }
  package enum Reason: String, Codable, Sendable {
    case userStop, microphoneMuted, voiceEnded, sessionClosed, speechDetected, recognizedWords
    case recognitionPriority, interactivePriority, incompatibleMemory, runtimeCancellation
    case emptyRecognition, explicitContinuation, playbackInterruption
  }
  package enum Phase: String, Codable, Sendable {
    case loading, ready, preparingMicrophone, listening, finalizing, thinking, preparingVoice
    case speaking, finished, chat, talk
  }
  package enum Metric: String, Codable, Sendable {
    case firstText, firstPCM, firstAudio, endpoint, recognitionFinalized, voicePrepared
    case contextMessages, contextToolResults, replyToolCalls
  }
  package enum Fault: String, Codable, Sendable {
    case permissionDenied, captureUnavailable, captureInterrupted, audioProcessing
    case transcription, recordingSave, finalization, unknown, textGeneration, speechSynthesis
  }

  package let area: Area
  package let action: Action
  package let operation: UUID?
  package var relatedOperation: UUID?
  package var reason: Reason?
  package var phase: Phase?
  package var failure: DiagnosticFailure?
  package var fault: Fault?
  package var metric: Metric?
  package var milliseconds: Double?
  package var count: Int?
  package private(set) var model: String?
  package private(set) var provider: String?

  package init(_ area: Area, _ action: Action, operation: UUID? = nil) {
    self.area = area
    self.action = action
    self.operation = operation
  }

  package func because(_ reason: Reason) -> Self {
    var event = self
    event.reason = reason
    return event
  }

  package func failing(_ error: any Error) -> Self {
    var event = self
    event.failure = DiagnosticFailure(error)
    return event
  }

  /// Call only with catalog identifiers, never display names or user-supplied text.
  package func using(model: String, provider: String) -> Self {
    var event = self
    event.model = Self.identifier(model)
    event.provider = Self.identifier(provider)
    return event
  }

  func validated() -> Self {
    var event = self
    event.model = model.flatMap(Self.identifier)
    event.provider = provider.flatMap(Self.identifier)
    event.failure = failure?.validated()
    if let milliseconds, !milliseconds.isFinite || milliseconds < 0 {
      event.milliseconds = nil
    }
    if let count { event.count = max(0, count) }
    return event
  }

  static func identifier(_ value: String) -> String? {
    guard !value.isEmpty, value.utf8.count <= 96,
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || [45, 46, 95].contains($0)
      })
    else { return nil }
    return value
  }
}
