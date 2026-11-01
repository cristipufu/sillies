import Foundation
import SilliesCore
import SilliesReasoning
import SilliesTTS

/// Bounded text delivery and sentence assembly live off the UI actor.
actor ChatTurnStream {
  private static let presentationInterval: Duration = .milliseconds(50)
  let speech = SpeechTextStream()
  private var text = ""
  private var phrases = SpokenPhraseBuffer()
  private var speechStopped = false
  private var lastPresented = ""
  private var lastPresentation = ContinuousClock.now
  private let receive: @Sendable (String) async -> Void
  init(receive: @escaping @Sendable (String) async -> Void) { self.receive = receive }

  func append(_ delta: String) async throws {
    try Task.checkCancellation()
    guard delta.utf8.count <= ChatContext.maximumMessageBytes - text.utf8.count,
      text.count + delta.count <= ChatContext.maximumMessageCharacters
    else {
      throw SessionFailure(
        category: .textGeneration,
        message: String(
          localized:
            "The local text model returned an incomplete response. Your source is unchanged."))
    }
    text += delta
    let ready = phrases.append(delta)
    if lastPresented.isEmpty || !ready.isEmpty
      || lastPresentation.duration(to: .now) >= Self.presentationInterval
    {
      await publish()
    }
    try await enqueue(ready)
  }

  func finish(_ completedText: String) async throws {
    guard
      text.trimmingCharacters(in: .whitespacesAndNewlines)
        == completedText.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      throw SessionFailure(
        category: .textGeneration,
        message: String(
          localized:
            "The local text model returned an incomplete response. Your source is unchanged."))
    }
    await publish()
    try await enqueue(phrases.finish())
    await speech.finish()
  }
  func cancel() async {
    await publish()
    speechStopped = true
    await speech.cancel()
  }
  func stopSpeech() async {
    speechStopped = true
    await speech.cancel()
  }
  private func enqueue(_ ready: [String]) async throws {
    guard !speechStopped else { return }
    for phrase in ready {
      do { try await speech.append(phrase) } catch is CancellationError {
        try Task.checkCancellation()
        // A voice failure ends only the audio branch. Text generation continues.
        speechStopped = true
        return
      }
    }
  }
  private func publish() async {
    guard text != lastPresented else { return }
    lastPresented = text
    lastPresentation = .now
    await receive(text)
  }
}
