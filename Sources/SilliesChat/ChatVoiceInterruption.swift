import Foundation

/// A possible interruption pauses output while recognition decides whether any words were spoken.
@MainActor final class ChatVoiceInterruption {
  private struct Candidate {
    let turnID: UUID
    let phase: ChatSession.Phase
  }
  private let output: any ChatSpeechOutput
  private var candidate: Candidate?
  private var control: Task<Void, Never>?
  var isActive: Bool { candidate != nil }

  init(output: any ChatSpeechOutput) { self.output = output }
  deinit { control?.cancel() }

  func begin(turnID: UUID, phase: ChatSession.Phase) {
    guard candidate == nil else { return }
    candidate = .init(turnID: turnID, phase: phase)
    let preceding = control
    control = Task { [output] in
      await preceding?.value
      guard !Task.isCancelled else { return }
      await output.pause(id: turnID)
    }
  }

  func resume(turnID: UUID) -> ChatSession.Phase? {
    guard let candidate, candidate.turnID == turnID else { return nil }
    self.candidate = nil
    let preceding = control
    control = Task { [output] in
      await preceding?.value
      guard !Task.isCancelled else { return }
      await output.resume(id: turnID)
    }
    return candidate.phase
  }

  func cancel() {
    candidate = nil
    control?.cancel()
    control = nil
  }
}
