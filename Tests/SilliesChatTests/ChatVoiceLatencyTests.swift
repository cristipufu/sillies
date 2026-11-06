import Foundation
import SilliesAudio
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesChat

@Test @MainActor func chatVoiceTimingIncludesAcousticSilenceBeforeRecognitionAndPlayback() throws {
  let now = ProcessInfo.processInfo.systemUptime
  let timing = try #require(VoiceEndpointTiming(lastSpeechSample: now - 1, detected: now - 0.1))
  let delivery = ChatTurnDelivery(started: .now, endpoint: timing)
  let attempt = UUID()
  delivery.beginSpeech(attempt)
  delivery.receivedText()
  delivery.received(.milestone(.firstPCM), from: attempt)
  delivery.received(.milestone(.audibleOutput(now + 0.2)), from: attempt)
  #expect(try #require(delivery.snapshot.endpoint) > .seconds(0.89))
  #expect(try #require(delivery.snapshot.endpoint) < .seconds(0.91))
  #expect(try #require(delivery.snapshot.recognitionFinalized) >= .seconds(1))
  #expect(try #require(delivery.snapshot.firstText) >= .seconds(1))
  #expect(try #require(delivery.snapshot.firstPCM) >= .seconds(1))
  #expect(try #require(delivery.snapshot.firstAudio) >= .seconds(1.19))
  #expect(VoiceEndpointTiming(lastSpeechSample: .nan, detected: now) == nil)
  #expect(VoiceEndpointTiming(lastSpeechSample: now + 1, detected: now) == nil)
}

@Test func chatStartsVoicePreparationBeforeACompletePhraseExists() async throws {
  let stream = ChatTurnStream(receive: { _ in })
  let started = Task { try await stream.speech.waitForTextStart() }
  try await stream.append("Hello")
  #expect(try await started.value)
  try await stream.finish("Hello")
  #expect(try await stream.speech.next() == "Hello")
  #expect(try await stream.speech.next() == nil)
}

@Test func chatReleasesAnOpeningPhraseDuringSlowUnpunctuatedGeneration() async throws {
  let events = Mutex(0)
  let stream = ChatTurnStream(
    receive: { _ in }, milestone: { _ in events.withLock { $0 += 1 } },
    openingPhraseDelay: .milliseconds(20))
  let text = "Here is a helpful opening with more to come"
  try await stream.append(text)
  for _ in 0..<100 {
    if events.withLock({ $0 }) > 0 { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(events.withLock { $0 } == 1)
  // Finish only after the first phrase has been released. No model or hardware is involved.
  try await stream.finish(text)
  var spoken: [String] = []
  while let phrase = try await stream.speech.next() { spoken.append(phrase) }
  #expect(spoken.count == 2)
  #expect(spoken.joined(separator: " ") == text)
}

@Test func chatCancellationStopsTheOpeningDeadlineWithoutLateSpeech() async throws {
  let events = Mutex(0)
  let stream = ChatTurnStream(
    receive: { _ in }, milestone: { _ in events.withLock { $0 += 1 } },
    openingPhraseDelay: .milliseconds(20))
  try await stream.append("Here is an unfinished opening with")
  await stream.cancel()
  try await Task.sleep(for: .milliseconds(50))
  #expect(events.withLock { $0 } == 0)
  await #expect(throws: CancellationError.self) { try await stream.speech.next() }
}

@Test @MainActor func chatAudioTimingWaitsForAudibleDeviceOutput() {
  let delivery = ChatTurnDelivery(started: .now)
  let attempt = UUID()
  delivery.beginSpeech(attempt)
  delivery.receivedText()
  delivery.received(.milestone(.firstPCM), from: attempt)
  delivery.received(.speaking(level: 0.8), from: attempt)
  #expect(delivery.snapshot.firstPCM != nil)
  #expect(delivery.snapshot.firstAudio == nil)
  delivery.received(.milestone(.audibleOutput(ProcessInfo.processInfo.systemUptime)), from: attempt)
  #expect(delivery.snapshot.firstAudio != nil)
}

@Test func readySpeechDoesNotWaitForBlockedTextPresentation() async throws {
  let (entered, entry) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let phraseReady = Mutex(false)
  let stream = ChatTurnStream(
    receive: { _ in
      entry.yield(())
      for await _ in released { break }
    }, milestone: { _ in phraseReady.withLock { $0 = true } })
  let text = "This complete sentence is ready to speak. "
  let append = Task { try await stream.append(text) }
  for await _ in entered { break }
  // The renderer is deliberately suspended, not delayed by an arbitrary test sleep.
  #expect(phraseReady.withLock { $0 })
  release.yield(())
  try await append.value
  try await stream.finish(text)
  #expect(try await stream.speech.next() == text.trimmingCharacters(in: .whitespaces))
  #expect(try await stream.speech.next() == nil)
}

@Test func cancellationDiscardsSpeechWhileTextPresentationIsSuspended() async throws {
  let (entered, entry) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let stream = ChatTurnStream(
    receive: { _ in
      entry.yield(())
      for await _ in released { break }
    }, openingPhraseDelay: .seconds(60))
  let append = Task { try await stream.append("An unfinished phrase") }
  for await _ in entered { break }
  let cancellation = Task { await stream.cancel() }
  await #expect(throws: CancellationError.self) { try await stream.speech.next() }
  release.yield(())
  await cancellation.value
  try await append.value
  await #expect(throws: CancellationError.self) { try await stream.speech.next() }
}
