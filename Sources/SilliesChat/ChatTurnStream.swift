import Foundation
import SilliesCore
import SilliesReasoning
import SilliesTTS

/// Bounded text delivery and sentence assembly live off the UI actor.
package actor ChatTurnStream {
  private static let presentationInterval: Duration = .milliseconds(50)
  package static let defaultOpeningPhraseDelay: Duration = .milliseconds(350)
  private let openingPhraseDelay: Duration
  package let speech = SpeechTextStream()
  private var text = ""
  private var phrases = SpokenPhraseBuffer()
  private var speechStopped = false
  private var lastSubmitted = ""
  private var lastSubmission = ContinuousClock.now
  private var openingDeadline: Task<Void, Never>?
  private var openingDeadlineReached = false
  private var reportedPhrase = false
  private let presentation: ChatTextPresentation
  private let milestone: @Sendable (SpeechDeliveryMilestone) -> Void
  package init(
    receive: @escaping @Sendable (String) async -> Void,
    milestone: @escaping @Sendable (SpeechDeliveryMilestone) -> Void = { _ in },
    openingPhraseDelay: Duration = ChatTurnStream.defaultOpeningPhraseDelay
  ) {
    presentation = ChatTextPresentation(receive: receive)
    self.milestone = milestone
    self.openingPhraseDelay = openingPhraseDelay
  }

  package func append(_ delta: String) async throws {
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
    if !delta.isEmpty { await speech.textStarted() }
    var ready = phrases.append(delta)
    if openingDeadlineReached { ready += phrases.flushOpeningPhrase() }
    if phrases.hasOpeningPhrase { cancelOpeningDeadline() } else { armOpeningDeadline() }
    try await enqueue(ready)
    if lastSubmitted.isEmpty || !ready.isEmpty
      || lastSubmission.duration(to: .now) >= Self.presentationInterval
    {
      await publish()
    }
  }

  package func finish(_ completedText: String) async throws {
    cancelOpeningDeadline()
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
    try await enqueue(phrases.finish())
    await speech.finish()
    await publish()
    await presentation.finish()
  }
  package func cancel() async {
    cancelOpeningDeadline()
    speechStopped = true
    await speech.cancel()
    await publish()
    await presentation.finish()
  }
  func stopSpeech() async {
    cancelOpeningDeadline()
    speechStopped = true
    await speech.cancel()
  }
  private func enqueue(_ ready: [String]) async throws {
    guard !speechStopped else { return }
    for phrase in ready {
      if !reportedPhrase {
        reportedPhrase = true
        milestone(.phraseReady)
      }
      do { try await speech.append(phrase) } catch is CancellationError {
        try Task.checkCancellation()
        // A voice failure ends only the audio branch. Text generation continues.
        speechStopped = true
        return
      }
    }
  }
  private func publish() async {
    guard text != lastSubmitted else { return }
    lastSubmitted = text
    lastSubmission = .now
    await presentation.submit(text)
  }

  private func armOpeningDeadline() {
    guard openingDeadline == nil, !openingDeadlineReached, !speechStopped else { return }
    let delay = openingPhraseDelay
    openingDeadline = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      await self?.releaseOpeningPhrase()
    }
  }

  private func releaseOpeningPhrase() async {
    guard !speechStopped, !Task.isCancelled else { return }
    openingDeadlineReached = true
    openingDeadline = nil
    do { try await enqueue(phrases.flushOpeningPhrase()) } catch {
      speechStopped = true
      await speech.fail(error)
    }
  }

  private func cancelOpeningDeadline() {
    openingDeadline?.cancel()
    openingDeadline = nil
  }
}
