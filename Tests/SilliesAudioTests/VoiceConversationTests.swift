import AVFoundation
import CoreMedia
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
  try await harness.beginSpeech()
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
  try await harness.beginSpeech()
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

@Test(arguments: [128, 512, 4_800])
func voicePlaybackReferenceIsBoundedAndIgnoresStoppedAndInvalidInput(sampleCount: Int) {
  let reference = VoicePlaybackReference()
  let frame = AudioRenderFrame(
    samples: [Float](repeating: 0.1, count: sampleCount), sampleRate: 48_000, startTime: 100)
  reference.append(frame)
  #expect(reference.drain().isEmpty)
  reference.start()
  for _ in 0..<10_000 { reference.append(frame) }
  let frames = reference.drain()
  #expect(!frames.isEmpty)
  #expect(frames.count <= 512)
  // Small native quanta must retain at least a second of reference when capture is briefly busy.
  let retainedSamples = frames.reduce(0) { $0 + $1.samples.count }
  #expect(retainedSamples >= 48_000)
  #expect(retainedSamples <= 192_000)
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
  let warmed = Mutex(0)
  let channels = Mutex(0)
  func makeCapture(
    finishTimeout: TimeInterval = 1, warm: @escaping @Sendable () async throws -> Void = {}
  ) -> VoiceConversationCapture {
    VoiceConversationCapture(
      configuration: .init(kind: .chat, target: nil, recordingURL: nil, language: fixtureEnglish),
      reference: VoicePlaybackReference(),
      resources: .init(
        audio: .init(
          queue: queue,
          microphone: { [microphone] receive, failure in
            microphone.receive.withLock { $0 = receive }
            microphone.failure.withLock { $0 = failure }
            return microphone
          },
          speech: { [self] _, output, _ in
            channels.withLock { $0 += 1 }
            speech.output.withLock { $0 = output }
            return speech
          }, finishTimeout: finishTimeout),
        warmSpeech: { [self] in
          warmed.withLock { $0 += 1 }
          try await warm()
        }),
      update: { [self] event in
        if case .capturing = event { capturing.withLock { $0 += 1 } }
      })
  }
  func beginSpeech() async throws {
    microphone.receive.withLock { $0 }?(try conversationAudio(.speech))
    try await wait { self.channels.withLock { $0 } == 1 }
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
  let receive = Mutex<(@Sendable (AudioCaptureInputQueue.Packet) -> Void)?>(nil)
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

@Test func voiceConversationWarmsWithoutReservingRecognitionDuringInitialSilence() async throws {
  let harness = ConversationHarness()
  let capture = harness.makeCapture()
  capture.start()
  try await harness.wait { harness.capturing.withLock { $0 } == 1 }
  #expect(harness.warmed.withLock { $0 } == 1)
  #expect(harness.channels.withLock { $0 } == 0)
  harness.microphone.receive.withLock { $0 }?(try conversationAudio(.silence))
  await withCheckedContinuation { continuation in harness.queue.async { continuation.resume() } }
  #expect(harness.channels.withLock { $0 } == 0)
  let result = Mutex<AudioCaptureResult?>(nil)
  capture.finish { value in result.withLock { $0 = value } }
  try await harness.wait { result.withLock { $0 != nil } }
  #expect(result.withLock { $0?.failure } == nil)
}

private enum ConversationSignal { case speech, silence }

/// Deterministic voiced harmonics exercise the real VAD and queue, without a device or model.
private func conversationAudio(_ signal: ConversationSignal) throws -> AudioCaptureInputQueue.Packet
{
  let rate = 16_000
  let frames = rate
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1))
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
  buffer.frameLength = AVAudioFrameCount(frames)
  let samples = try #require(buffer.floatChannelData?[0])
  for index in 0..<frames {
    let time = Double(index) / Double(rate)
    let phase = 2 * Double.pi * (180 * time + 12 * sin(2 * Double.pi * 3 * time))
    samples[index] =
      signal == .silence
      ? 0 : Float(0.2 * sin(phase) + 0.1 * sin(3 * phase) + 0.05 * sin(7 * phase))
  }
  var description: CMAudioFormatDescription?
  #expect(
    CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, asbd: format.streamDescription,
      layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
      formatDescriptionOut: &description) == noErr)
  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: Int32(rate)),
    presentationTimeStamp: CMTime(seconds: 100, preferredTimescale: Int32(rate)),
    decodeTimeStamp: .invalid)
  var sample: CMSampleBuffer?
  #expect(
    CMSampleBufferCreate(
      allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
      makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: frames,
      sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
      sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
  let ready = try #require(sample)
  #expect(
    CMSampleBufferSetDataBufferFromAudioBufferList(
      ready, blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList)
      == noErr)
  return try #require(AudioCaptureInputQueue.Packet(sample: ready, source: .microphone))
}

@Test func voiceConversationCancelledDuringWarmupNeverStartsTheMicrophoneLate() async throws {
  let harness = ConversationHarness()
  let warmup = SuspendedConversationWarmup()
  let capture = harness.makeCapture(warm: { await warmup.wait() })
  capture.start()
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while await !warmup.hasStarted, ContinuousClock.now < deadline { await Task.yield() }
  #expect(await warmup.hasStarted)
  let result = Mutex<AudioCaptureResult?>(nil)
  capture.finish { value in result.withLock { $0 = value } }
  try await harness.wait { result.withLock { $0 != nil } }
  await warmup.complete()
  try await Task.sleep(for: .milliseconds(20))
  #expect(harness.microphone.starts.withLock { $0 } == 0)
  #expect(harness.channels.withLock { $0 } == 0)
  #expect(harness.capturing.withLock { $0 } == 0)
  #expect(result.withLock { $0?.failure } == nil)
}

private actor SuspendedConversationWarmup {
  private var continuation: CheckedContinuation<Void, Never>?
  var hasStarted: Bool { continuation != nil }
  func wait() async { await withCheckedContinuation { continuation = $0 } }
  func complete() {
    continuation?.resume()
    continuation = nil
  }
}
