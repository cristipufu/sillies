import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesCore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

@Test func voiceConversationStopsDeviceBeforeRecognizerDrainAndKeepsDetachedWordsSeparate()
  async throws
{
  let harness = ConversationHarness()
  let capture = harness.makeCapture()
  capture.start()
  capture.start()
  try await harness.wait { harness.capturing.withLock { $0 } == 1 }
  harness.speech.emit("Keep this last sentence")
  let turns = Mutex<[AudioCaptureResult]>([])
  let finishes = Mutex<[AudioCaptureResult]>([])
  capture.finishTurn { result in turns.withLock { $0.append(result) } }
  capture.finish { result in finishes.withLock { $0.append(result) } }
  capture.finish { result in finishes.withLock { $0.append(result) } }
  try await harness.wait { harness.microphone.stops.withLock { $0 } == 1 }
  #expect(finishes.withLock { $0.isEmpty })
  #expect(harness.microphone.starts.withLock { $0 } == 1)
  harness.speech.complete()
  harness.speech.complete()
  try await harness.wait { finishes.withLock { $0.count } == 2 }
  #expect(turns.withLock { $0.count } == 1)
  #expect(turns.withLock { $0.first?.plainText } == "Keep this last sentence")
  #expect(finishes.withLock { $0.allSatisfy { $0.transcript.isEmpty && $0.failure == nil } })
  capture.finish { result in finishes.withLock { $0.append(result) } }
  try await harness.wait { finishes.withLock { $0.count } == 3 }
  #expect(harness.microphone.stops.withLock { $0 } == 1)
}

@Test func voiceConversationFinalizationDeadlineKeepsDraftAndRejectsLateCallbacks() async throws {
  let harness = ConversationHarness()
  let capture = harness.makeCapture(finishTimeout: 0.02)
  capture.start()
  try await harness.wait { harness.capturing.withLock { $0 } == 1 }
  harness.speech.emit("An unfinished thought")
  let results = Mutex<[AudioCaptureResult]>([])
  capture.finish { result in results.withLock { $0.append(result) } }
  try await harness.wait { results.withLock { !$0.isEmpty } }
  #expect(results.withLock { $0.first?.plainText } == "An unfinished thought")
  #expect(results.withLock { $0.first?.failure?.category } == .finalization)
  harness.speech.emit("Too late")
  harness.speech.complete()
  capture.finish { result in results.withLock { $0.append(result) } }
  try await harness.wait { results.withLock { $0.count } == 2 }
  #expect(results.withLock { $0.last?.plainText } == "An unfinished thought")
}

@Test func voiceConversationDeviceFailureRetainsTypedRecoveryAndStopsCapture() async throws {
  let harness = ConversationHarness()
  let capture = harness.makeCapture()
  capture.start()
  try await harness.wait { harness.capturing.withLock { $0 } == 1 }
  let failure = SessionFailure.permissionDenied(.openMicrophoneSettings)
  harness.microphone.failure.withLock { $0 }?(failure)
  try await harness.wait { harness.microphone.stops.withLock { $0 } == 1 }
  let results = Mutex<[AudioCaptureResult]>([])
  capture.finish { result in results.withLock { $0.append(result) } }
  harness.speech.complete()
  try await harness.wait { results.withLock { !$0.isEmpty } }
  #expect(results.withLock { $0.first?.failure } == failure)
}

@Test func voicePlaybackReferenceIsBoundedAndIgnoresStoppedAndInvalidInput() {
  let reference = VoicePlaybackReference()
  let frame = AudioRenderFrame(
    samples: [Float](repeating: 0.1, count: 4_800), sampleRate: 48_000, startTime: 100)
  reference.append(frame)
  #expect(reference.drain().isEmpty)
  reference.start()
  for _ in 0..<10_000 { reference.append(frame) }
  let frames = reference.drain()
  #expect(!frames.isEmpty)
  #expect(frames.count <= 64)
  #expect(frames.reduce(0) { $0 + $1.samples.count } <= 192_000)
  reference.append(.init(samples: [1], sampleRate: .nan, startTime: 1))
  reference.append(.init(samples: [1], sampleRate: 16_000, startTime: .infinity))
  #expect(reference.drain().isEmpty)
  reference.append(frame)
  reference.stop()
  reference.append(frame)
  #expect(reference.drain().isEmpty)
}

private final class ConversationHarness: Sendable {
  let queue = DispatchQueue(label: "sillies.test.voice-conversation")
  let microphone = ConversationMicrophone()
  let speech = ConversationRecognizer()
  let capturing = Mutex(0)
  func makeCapture(finishTimeout: TimeInterval = 1) -> VoiceConversationCapture {
    VoiceConversationCapture(
      configuration: .init(kind: .chat, target: nil, recordingURL: nil, language: fixtureEnglish),
      reference: VoicePlaybackReference(),
      dependencies: .init(
        queue: queue,
        microphone: { [microphone] _, failure in
          microphone.failure.withLock { $0 = failure }
          return microphone
        },
        speech: { [speech] _, output, _ in
          speech.output.withLock { $0 = output }
          return speech
        }, finishTimeout: finishTimeout),
      update: { [self] event in
        if case .capturing = event { capturing.withLock { $0 += 1 } }
      })
  }
  func wait(_ predicate: @Sendable () -> Bool) async throws {
    for _ in 0..<200 {
      await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Voice capture did not complete within one second")
  }
}

private final class ConversationMicrophone: MicrophoneCapture {
  let starts = Mutex(0)
  let stops = Mutex(0)
  let failure = Mutex<AudioCaptureDependencies.Failure?>(nil)
  func start() async throws -> String {
    starts.withLock { $0 += 1 }
    return "Fixture microphone"
  }
  func stop(completion: @escaping @Sendable () -> Void) {
    stops.withLock { $0 += 1 }
    completion()
    completion()
  }
}

private final class ConversationRecognizer: LocalSpeechChannel {
  let output = Mutex<LocalSpeechFactory.Output?>(nil)
  let completion = Mutex<(@Sendable () -> Void)?>(nil)
  func append(_ buffer: AVAudioPCMBuffer) {}
  func emit(_ text: String) { output.withLock { $0 }?(.init(text: text, isFinal: false)) }
  func finish(completion: @escaping @Sendable () -> Void) {
    self.completion.withLock { $0 = completion }
  }
  func complete() { completion.withLock { $0 }?() }
  func cancel() {}
}
