import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

@Test func duplicateRecognizerFinishCannotCompleteAnotherSourcesDrain() async {
  let queue = DispatchQueue(label: "sillies.test.duplicate-speech-completion")
  let meeting = LifecycleSpeechChannel()
  let microphone = LifecycleSpeechChannel()
  let completed = Mutex(0)
  let group = SpeechChannelGroup(
    id: UUID(), channels: [.application: meeting, .microphone: microphone], queue: queue)
  await onSpeechQueue(queue) {
    group.finish(reason: .sessionEnd) { _ in completed.withLock { $0 += 1 } }
  }
  meeting.complete()
  meeting.complete()
  await onSpeechQueue(queue) {}
  #expect(completed.withLock { $0 } == 0)
  microphone.complete()
  await onSpeechQueue(queue) {}
  #expect(completed.withLock { $0 } == 1)
  meeting.complete()
  microphone.complete()
  await onSpeechQueue(queue) {}
  #expect(completed.withLock { $0 } == 1)
}

@Test func recognizerTimeoutCancelsAllSourcesAndIgnoresLateCompletions() async {
  let queue = DispatchQueue(label: "sillies.test.speech-timeout")
  let channel = LifecycleSpeechChannel()
  let group = SpeechChannelGroup(
    id: UUID(), channels: [.microphone: channel], queue: queue,
    timeouts: .init(languageChange: 0, sessionEnd: 0))
  let count = Mutex(0)
  let notice: String? = await withCheckedContinuation { continuation in
    queue.async {
      group.finish(reason: .sessionEnd) { notice in
        let first = count.withLock {
          $0 += 1
          return $0 == 1
        }
        if first { continuation.resume(returning: notice) }
      }
    }
  }
  #expect(notice?.contains("preserved") == true)
  #expect(channel.wasCancelled)
  channel.complete()
  await onSpeechQueue(queue) {}
  #expect(count.withLock { $0 } == 1)
}

@Test func cancellationRejectsRecognizerPreparedAfterSessionEnded() async {
  let queue = DispatchQueue(label: "sillies.test.delayed-speech-preparation")
  let gate = DelayedSpeechFactory()
  let events = Mutex(0)
  let startResults = Mutex(0)
  let pipeline = SessionSpeechPipeline(
    configuration: .init(
      sources: [.microphone], queue: queue, makeChannel: { _, _, _ in await gate.make() })
  ) { _ in events.withLock { $0 += 1 } }
  await onSpeechQueue(queue) {
    pipeline.start(language: fixtureEnglish) { result in
      startResults.withLock { $0 += 1 }
      if case .success = result { Issue.record("Cancelled preparation must not start capture.") }
    }
  }
  var started = gate.started.makeAsyncIterator()
  _ = await started.next()
  await onSpeechQueue(queue) { pipeline.cancel() }
  #expect(startResults.withLock { $0 } == 1)
  gate.release()
  var cancelled = gate.channel.cancellations.makeAsyncIterator()
  _ = await cancelled.next()
  await onSpeechQueue(queue) {}
  #expect(events.withLock { $0 } == 0)
  #expect(startResults.withLock { $0 } == 1)
}

@Test func partialRecognizerPreparationFailureReleasesAlreadyCreatedChannels() async {
  let queue = DispatchQueue(label: "sillies.test.partial-speech-failure")
  let channel = LifecycleSpeechChannel()
  let calls = Mutex(0)
  let pipeline = SessionSpeechPipeline(
    configuration: .init(
      sources: [.application, .microphone], queue: queue,
      makeChannel: { _, _, _ in
        let first = calls.withLock {
          $0 += 1
          return $0 == 1
        }
        if first { return channel }
        throw AudioCaptureFailure.unavailable("Fixture initialization failed")
      })
  ) { _ in }
  let result: Result<Void, Error> = await withCheckedContinuation { continuation in
    queue.async { pipeline.start(language: fixtureEnglish) { continuation.resume(returning: $0) } }
  }
  if case .success = result { Issue.record("A partial startup cannot succeed.") }
  #expect(channel.wasCancelled)
  await onSpeechQueue(queue) { pipeline.cancel() }
}

private final class LifecycleSpeechChannel: LocalSpeechChannel {
  private struct State {
    var completion: (@Sendable () -> Void)?
    var cancelled = false
  }
  private let state = Mutex(State())
  let cancellations: AsyncStream<Void>
  private let cancelled: AsyncStream<Void>.Continuation
  init() {
    (cancellations, cancelled) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }
  var wasCancelled: Bool { state.withLock { $0.cancelled } }
  func append(_ buffer: AVAudioPCMBuffer) {}
  func finish(completion: @escaping @Sendable () -> Void) {
    state.withLock { $0.completion = completion }
  }
  func complete() { state.withLock { $0.completion }?() }
  func cancel() {
    state.withLock { $0.cancelled = true }
    cancelled.yield(())
    cancelled.finish()
  }
}

private final class DelayedSpeechFactory: Sendable {
  let channel = LifecycleSpeechChannel()
  let started: AsyncStream<Void>
  private let start: AsyncStream<Void>.Continuation
  private let pending = Mutex<CheckedContinuation<any LocalSpeechChannel, Never>?>(nil)
  init() { (started, start) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1)) }
  func make() async -> any LocalSpeechChannel {
    await withCheckedContinuation { continuation in
      pending.withLock { $0 = continuation }
      start.yield(())
      start.finish()
    }
  }
  func release() {
    let continuation = pending.withLock { pending in
      defer { pending = nil }
      return pending
    }
    continuation?.resume(returning: channel)
  }
}

private func onSpeechQueue(_ queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) async {
  await withCheckedContinuation { continuation in
    queue.async {
      work()
      continuation.resume()
    }
  }
}
