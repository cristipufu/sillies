import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesCore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

@Test func audioCaptureSequenceRepeatedStartPauseResumeAndFinishPreservesOneSession() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService()
  service.start()
  service.start()
  await harness.events.waitForCapture()
  #expect(harness.microphone.startCount == 1)
  harness.clock.withLock { $0 = 110 }
  service.pause()
  service.pause()
  await harness.checkpoint()
  harness.clock.withLock { $0 = 140 }
  service.resume()
  service.resume()
  await harness.checkpoint()
  harness.speech.emit("Keep the final words")
  harness.clock.withLock { $0 = 150 }
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  #expect(harness.microphone.stopCount == 1)
  harness.microphone.completeStops()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let first = await iterator.next()
  let second = await iterator.next()
  #expect(first?.duration == 20)
  #expect(second?.duration == 20)
  #expect(first?.transcript.contains("Keep the final words") == true)
  #expect(first?.failure == nil)
  // A subscriber arriving after completion receives the same immutable result.
  service.finish { completion.yield($0) }
  let third = await iterator.next()
  #expect(third?.transcript == first?.transcript)
  #expect(harness.microphone.stopCount == 1)
  completion.finish()
}

@Test func audioCaptureSequenceFailureRejectsResumeLanguageChangesAndLateStart() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService()
  service.start()
  await harness.events.waitForCapture()
  harness.clock.withLock { $0 = 110 }
  service.pause()
  await harness.checkpoint()
  harness.clock.withLock { $0 = 200 }
  harness.microphone.fail("Input permission was revoked")
  await harness.events.waitForFailure()
  service.resume()
  service.start()
  service.changeLanguage(fixtureFrench)
  await harness.checkpoint()
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  #expect(result?.duration == 10)
  #expect(result?.failure?.message == "Input permission was revoked")
  #expect(harness.microphone.startCount == 1)
  #expect(harness.events.captureCount == 1)
  completion.finish()
}

@Test func audioCaptureSequenceShutdownDuringPermissionPreparationRejectsLateCapture() async {
  let gate = CaptureStartupGate()
  let harness = CaptureLifecycleHarness(gate: gate)
  let service = harness.makeService()
  service.start()
  var starts = harness.microphone.starts.makeAsyncIterator()
  _ = await starts.next()
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  #expect(result?.duration == 0)
  gate.release()
  var returns = harness.microphone.returns.makeAsyncIterator()
  _ = await returns.next()
  service.start()
  service.resume()
  await harness.checkpoint()
  #expect(harness.events.captureCount == 0)
  #expect(harness.microphone.startCount == 1)
  completion.finish()
}

@Test func audioCaptureSequenceFinishRetainsWorkAndReleasesOwnerAfterDraining() async {
  let harness = CaptureLifecycleHarness()
  var service: AudioTranscriptionService? = harness.makeService()
  weak var retained = service
  service?.start()
  await harness.events.waitForCapture()
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service?.finish { completion.yield($0) }
  service = nil
  await harness.checkpoint()
  #expect(retained != nil)
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  _ = await iterator.next()
  await harness.checkpoint()
  #expect(retained == nil)
  completion.finish()
}

@Test func audioCaptureSequenceFinalizationDeadlinePreservesResultAndIgnoresLateStops() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService(finishTimeout: 0)
  service.start()
  await harness.events.waitForCapture()
  harness.speech.emit("Preserved before timeout")
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  var iterator = results.makeAsyncIterator()
  let timedOut = await iterator.next()
  #expect(timedOut?.failure?.message.contains("timed out") == true)
  #expect(timedOut?.transcript.contains("Preserved before timeout") == true)
  harness.microphone.completeStops()
  harness.microphone.completeStops()
  harness.microphone.fail("Late input error")
  service.finish { completion.yield($0) }
  let repeated = await iterator.next()
  #expect(repeated?.failure == timedOut?.failure)
  #expect(repeated?.transcript == timedOut?.transcript)
  completion.finish()
}

@Test func audioCaptureSequenceShutdownBeforeStartNeverRequestsDevices() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService()
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  service.start()
  service.pause()
  service.resume()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  await harness.checkpoint()
  #expect(result?.duration == 0)
  #expect(harness.microphone.startCount == 0)
  #expect(harness.events.captureCount == 0)
  completion.finish()
}

@Test func audioCaptureSequencePreservesTypedStartupFailureThroughFinalization() async {
  let denied = SessionFailure.permissionDenied(.openMicrophoneSettings)
  let harness = CaptureLifecycleHarness(startupFailure: denied)
  let service = harness.makeService()
  service.start()
  let received = await harness.events.waitForFailure()
  #expect(received == denied)
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  #expect(result?.failure == denied)
  #expect(harness.events.captureCount == 0)
  completion.finish()
}

@Test func transcriptionFailurePreservesRecordingAndAvailableTranscript() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService()
  service.start()
  await harness.events.waitForCapture()
  harness.speech.emit("Saved before recognition stopped")
  harness.speech.fail("Inference could not keep up")
  let failure = await harness.events.waitForTranscriptionStop()
  #expect(failure?.category == .transcription)
  #expect(harness.microphone.stopCount == 0)
  harness.clock.withLock { $0 = 120 }
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  #expect(result?.duration == 20)
  #expect(result?.transcript.contains("Saved before recognition stopped") == true)
  #expect(result?.failure?.category == .transcription)
  completion.finish()
}

@Test func diarizationPreparationFailurePreservesRecordingAndTheSavedNotice() async {
  let harness = CaptureLifecycleHarness()
  let service = harness.makeService(diarization: { _ in
    throw SpeechError.unavailable("Fixture speaker model failure")
  })
  service.start()
  await harness.events.waitForCapture()
  harness.speech.emit("Words survive unavailable speaker detection")
  #expect(harness.microphone.stopCount == 0)
  let (results, completion) = AsyncStream<AudioCaptureResult>.makeStream()
  service.finish { completion.yield($0) }
  await harness.checkpoint()
  harness.microphone.completeStops()
  var iterator = results.makeAsyncIterator()
  let result = await iterator.next()
  #expect(result?.failure == nil)
  #expect(result?.transcript.contains("Words survive") == true)
  #expect(result?.speakerDetectionNotice?.contains("Fixture speaker model failure") == true)
  completion.finish()
}

private final class CaptureLifecycleHarness: Sendable {
  let queue = DispatchQueue(label: "sillies.test.capture-lifecycle")
  let clock = Mutex(100.0)
  let microphone: LifecycleMicrophone
  let speech = CaptureSpeechChannel()
  let events = CaptureEvents()
  init(gate: CaptureStartupGate? = nil, startupFailure: SessionFailure? = nil) {
    microphone = LifecycleMicrophone(gate: gate, startupFailure: startupFailure)
  }
  func makeService(
    finishTimeout: TimeInterval? = nil, diarization: SpeakerDiarizationFactory.Make? = nil
  ) -> AudioTranscriptionService {
    var dependencies = AudioCaptureDependencies(
      queue: queue,
      microphone: { [microphone] _, failure in
        microphone.installFailure(failure)
        return microphone
      },
      speech: { [speech] _, output, failure in
        speech.install(output, failure: failure)
        return speech
      }, diarization: diarization, now: { [self] in clock.withLock { $0 } })
    if let finishTimeout { dependencies.finishTimeout = finishTimeout }
    return AudioTranscriptionService(
      configuration: .init(kind: .record, target: nil, recordingURL: nil, language: fixtureEnglish),
      dependencies: dependencies, onUpdate: { [events] in events.receive($0) })
  }
  func checkpoint() async {
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  }
}

private final class CaptureEvents: Sendable {
  private let updates: AsyncStream<AudioCaptureUpdate>
  private let continuation: AsyncStream<AudioCaptureUpdate>.Continuation
  private let captures = Mutex(0)
  init() { (updates, continuation) = AsyncStream.makeStream() }
  var captureCount: Int { captures.withLock { $0 } }
  func receive(_ update: AudioCaptureUpdate) {
    if case .capturing = update { captures.withLock { $0 += 1 } }
    continuation.yield(update)
  }
  func waitForCapture() async {
    for await update in updates { if case .capturing = update { return } }
  }
  @discardableResult func waitForFailure() async -> SessionFailure? {
    for await update in updates { if case .failed(let failure) = update { return failure } }
    return nil
  }
  func waitForTranscriptionStop() async -> SessionFailure? {
    for await update in updates {
      if case .transcriptionStopped(let failure) = update { return failure }
    }
    return nil
  }
}

private final class LifecycleMicrophone: MicrophoneCapture {
  private struct State {
    var starts = 0
    var completions: [@Sendable () -> Void] = []
    var failure: (@Sendable (SessionFailure) -> Void)?
  }
  private let state = Mutex(State())
  private let gate: CaptureStartupGate?
  private let startupFailure: SessionFailure?
  let starts: AsyncStream<Void>
  private let started: AsyncStream<Void>.Continuation
  let returns: AsyncStream<Void>
  private let returned: AsyncStream<Void>.Continuation
  init(gate: CaptureStartupGate?, startupFailure: SessionFailure?) {
    self.gate = gate
    self.startupFailure = startupFailure
    (starts, started) = AsyncStream.makeStream()
    (returns, returned) = AsyncStream.makeStream()
  }
  var startCount: Int { state.withLock { $0.starts } }
  var stopCount: Int { state.withLock { $0.completions.count } }
  func installFailure(_ failure: @escaping @Sendable (SessionFailure) -> Void) {
    state.withLock { $0.failure = failure }
  }
  func start() async throws -> String {
    state.withLock { $0.starts += 1 }
    started.yield(())
    await gate?.wait()
    returned.yield(())
    if let startupFailure { throw startupFailure }
    return "Fixture microphone"
  }
  func stop(completion: @escaping @Sendable () -> Void) {
    state.withLock { $0.completions.append(completion) }
  }
  func completeStops() { for callback in state.withLock({ $0.completions }) { callback() } }
  func fail(_ message: String) {
    state.withLock { $0.failure }?(.init(category: .captureInterrupted, message: message))
  }
}

private final class CaptureSpeechChannel: LocalSpeechChannel {
  private let output = Mutex<LocalSpeechFactory.Output?>(nil)
  private let failure = Mutex<LocalSpeechFactory.Failure?>(nil)
  func install(
    _ output: @escaping LocalSpeechFactory.Output, failure: @escaping LocalSpeechFactory.Failure
  ) {
    self.output.withLock { $0 = output }
    self.failure.withLock { $0 = failure }
  }
  func fail(_ message: String) { failure.withLock { $0 }?(message) }
  func emit(_ text: String) { output.withLock { $0 }?(SpeechPhrase(text: text, isFinal: true)) }
  func append(_ buffer: AVAudioPCMBuffer) {}
  func finish(completion: @escaping @Sendable () -> Void) { completion() }
  func cancel() {}
}

private final class CaptureStartupGate: Sendable {
  private enum State {
    case waiting(CheckedContinuation<Void, Never>?)
    case released
  }
  private let state = Mutex(State.waiting(nil))
  func wait() async {
    await withCheckedContinuation { continuation in
      let ready = state.withLock { state in
        if case .released = state { return true }
        state = .waiting(continuation)
        return false
      }
      if ready { continuation.resume() }
    }
  }
  func release() {
    let pending = state.withLock { state -> CheckedContinuation<Void, Never>? in
      defer { state = .released }
      guard case .waiting(let pending) = state else { return nil }
      return pending
    }
    pending?.resume()
  }
}
