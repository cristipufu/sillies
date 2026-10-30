import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

@Test func diarizationKeepsTextVisibleWhileWaitingAndPreservesItOnFailure() async throws {
  let queue = DispatchQueue(label: "sillies.test.diarization")
  let output = Mutex<[SpeechPhrase]>([])
  let notices = Mutex<[String]>([])
  let channel = SpeakerFixtureChannel()
  let session = SessionDiarization(
    channels: [.application: channel], queue: queue,
    output: { phrase, _ in output.withLock { $0.append(phrase) } },
    notice: { message in notices.withLock { $0.append(message) } })
  await withCheckedContinuation { continuation in
    queue.async {
      let first = SpeechPhrase(
        text: "Hello", isFinal: true, startTime: 0, duration: 1, finalizedThrough: 1)
      session.receive(first, source: .application)
      #expect(output.withLock { $0.last?.text } == "Hello")
      #expect(output.withLock { $0.last?.isFinal } == false)
      session.receive(
        .init(
          start: 0, frameDuration: 0.1, speakerCount: 2,
          probabilities: Array(repeating: [Float(0.95), 0.01], count: 10).flatMap { $0 }),
        source: .application)
      #expect(output.withLock { $0.last?.isFinal } == true)
      #expect(output.withLock { $0.last?.speaker } == .identified(1))
      session.receive(
        .init(text: "Keep these words", isFinal: true, startTime: 1, duration: 1),
        source: .application)
      session.fail("Fixture failure", source: .application)
      #expect(output.withLock { $0.last?.text } == "Keep these words")
      #expect(output.withLock { $0.last?.isFinal } == true)
      #expect(output.withLock { $0.last?.speaker } == .unknown)
      session.receive(.init(text: "Still transcribing", isFinal: true), source: .application)
      #expect(output.withLock { $0.last?.text } == "Still transcribing")
      session.cancel()
      continuation.resume()
    }
  }
  #expect(notices.withLock { $0 } == ["Fixture failure"])
  #expect(channel.cancelled.withLock { $0 })
}

private final class SpeakerFixtureChannel: LocalSpeechChannel {
  let cancelled = Mutex(false)
  func append(_ buffer: AVAudioPCMBuffer) {}
  func finish(completion: @escaping @Sendable () -> Void) { completion() }
  func cancel() { cancelled.withLock { $0 = true } }
}
