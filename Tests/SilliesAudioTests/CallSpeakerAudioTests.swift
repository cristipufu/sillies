import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

private enum ObservationDelivery: CaseIterable, Sendable {
  case current, wrongWindow, stale, beforeResume
}

@Test(arguments: ObservationDelivery.allCases)
private func callSpeakerAudioBridgeValidatesSourceClockAndPauseBoundary(
  _ delivery: ObservationDelivery
) async throws {
  let queue = DispatchQueue(label: "sillies.test.call-speaker-bridge")
  let clock = Mutex(100.0)
  let channels = Mutex<[CallSpeechChannel]>([])
  let (started, didStart) = AsyncStream<Void>.makeStream()
  let target = WindowTargetCandidate(windowID: 7, processID: 42, appName: "Zoom", frame: .zero)
  let service = AudioTranscriptionService(
    configuration: .init(
      kind: .listen, target: target, recordingURL: nil,
      language: .init(id: "en-US", name: "English", isInstalled: true)),
    dependencies: .init(
      queue: queue,
      microphone: { _, _ in CallMicrophone() }, application: { _, _, _ in CallApplicationAudio() },
      speech: { _, output, _ in
        let channel = CallSpeechChannel(output: output)
        channels.withLock { $0.append(channel) }
        return channel
      }, now: { clock.withLock { $0 } }),
    onUpdate: { if case .capturing = $0 { didStart.yield(()) } })
  service.start()
  var starts = started.makeAsyncIterator()
  _ = await starts.next()
  if delivery == .beforeResume {
    clock.withLock { $0 = 101 }
    service.pause()
    await bridgeCheckpoint(queue)
    clock.withLock { $0 = 105 }
    service.resume()
    await bridgeCheckpoint(queue)
  }
  let name = try #require(CallSpeakerName(rawValue: "Alice"))
  for step in 0...20 {
    let wallTime = 100 + Double(step) / 2
    clock.withLock { $0 = delivery == .stale ? 200 : max(105, wallTime) }
    let capturedAt = delivery == .beforeResume ? 100 : wallTime
    // Current observations are delivered at their actual monotonic timestamp.
    if delivery == .current { clock.withLock { $0 = wallTime } }
    service.observeCallSpeakers(
      .init(
        source: .init(processID: 42, windowID: delivery == .wrongWindow ? 8 : 7),
        capturedAt: capturedAt, availability: .available, speaking: [name]))
    await bridgeCheckpoint(queue)
  }
  let speech = channels.withLock { $0 }
  try #require(speech.count == 2)
  speech[0].emit("Their original words", at: 2)
  speech[1].emit("My original words", at: 2)
  await bridgeCheckpoint(queue)
  let result: AudioCaptureResult = await withCheckedContinuation { continuation in
    service.finish { continuation.resume(returning: $0) }
  }
  let remote = try #require(result.segments.first(where: { $0.source == "Meeting" }))
  #expect(remote.automaticSpeakerName == (delivery == .current ? name : nil))
  #expect(remote.text == "Their original words")
  #expect(result.segments.first(where: { $0.source == "Microphone" })?.automaticSpeakerName == nil)
  if delivery == .current {
    #expect(result.transcript.contains("Meeting · Alice: Their original words"))
    #expect(result.originalTranscript?.contains("Meeting: Their original words") == true)
  } else {
    #expect(result.originalTranscript == nil)
  }
}

private func bridgeCheckpoint(_ queue: DispatchQueue) async {
  await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
}
private final class CallMicrophone: MicrophoneCapture {
  func start() async throws -> String { "Fixture" }
  func stop(completion: @escaping @Sendable () -> Void) { completion() }
}
private final class CallApplicationAudio: ApplicationCapture {
  func start() async throws {}
  func stop(completion: @escaping @Sendable (SessionFailure?) -> Void) { completion(nil) }
}
private final class CallSpeechChannel: LocalSpeechChannel {
  private let output: LocalSpeechFactory.Output
  init(output: @escaping LocalSpeechFactory.Output) { self.output = output }
  func emit(_ text: String, at time: Double) {
    output(.init(text: text, isFinal: true, startTime: time, duration: 2))
  }
  func append(_ buffer: AVAudioPCMBuffer) {}
  func finish(completion: @escaping @Sendable () -> Void) { completion() }
  func cancel() {}
}
