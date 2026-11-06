import Foundation

/// Keeps the recognition decision alive even when inference is preempted before UI delivery.
@MainActor final class ChatVoiceInterruption {
  enum Resolution {
    case resume(ChatSession.Phase)
    case recover
  }
  private enum Recognition { case awaitingWords, empty }
  private struct Candidate {
    let turnID: UUID
    let speechID: UUID
    let phase: ChatSession.Phase
    var recognition = Recognition.awaitingWords
    var wasPreempted = false
  }
  private let output: any ChatSpeechOutput
  private var candidate: Candidate?
  private var control: Task<Void, Never>?
  var isActive: Bool { candidate?.recognition == .awaitingWords }

  init(output: any ChatSpeechOutput) { self.output = output }
  deinit { control?.cancel() }

  func begin(turnID: UUID, speechID: UUID, phase: ChatSession.Phase) {
    guard !isActive else { return }
    candidate = .init(turnID: turnID, speechID: speechID, phase: phase)
    let preceding = control
    control = Task { [output] in
      await preceding?.value
      guard !Task.isCancelled else { return }
      await output.pause(id: speechID)
    }
  }

  func preempt(turnID: UUID, speechID: UUID, phase: ChatSession.Phase) -> Bool {
    if candidate?.turnID != turnID {
      candidate = .init(turnID: turnID, speechID: speechID, phase: phase)
    }
    candidate?.wasPreempted = true
    return candidate?.recognition == .empty
  }

  func resolveEmpty(turnID: UUID) -> Resolution? {
    guard var candidate, candidate.turnID == turnID else { return nil }
    candidate.recognition = .empty
    self.candidate = candidate
    if candidate.wasPreempted { return .recover }
    let preceding = control
    control = Task { [output] in
      await preceding?.value
      guard !Task.isCancelled else { return }
      await output.resume(id: candidate.speechID)
    }
    return .resume(candidate.phase)
  }

  func cancel() {
    candidate = nil
    control?.cancel()
    control = nil
  }
}
