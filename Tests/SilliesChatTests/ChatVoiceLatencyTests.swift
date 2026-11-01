import Foundation
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesChat

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
  delivery.receivedText()
  delivery.received(.milestone(.firstPCM))
  delivery.received(.speaking(level: 0.8))
  #expect(delivery.snapshot.firstPCM != nil)
  #expect(delivery.snapshot.firstAudio == nil)
  delivery.received(.milestone(.audibleOutput(ProcessInfo.processInfo.systemUptime)))
  #expect(delivery.snapshot.firstAudio != nil)
}
