import Foundation
import SilliesTTS
import SilliesVoicePlayback
import Synchronization
import Testing

private final class OutputProbe: VoiceOutputDevice, Sendable {
  let interruption = Mutex<(@Sendable () -> Void)?>(nil)
  let audible = Mutex<(@Sendable (TimeInterval) -> Void)?>(nil)
  func onAudibleOutput(_ receive: @escaping @Sendable (TimeInterval) -> Void) {
    audible.withLock { $0 = receive }
  }
  func onInterruption(_ receive: @escaping @Sendable () -> Void) {
    interruption.withLock { $0 = receive }
  }
  let completions = Mutex<[@Sendable () -> Void]>([])
  let stopCount = Mutex(0)
  func schedule(_ audio: SynthesizedAudio, completed: @escaping @Sendable () -> Void) throws {
    completions.withLock { $0.append(completed) }
  }
  func stop() { stopCount.withLock { $0 += 1 } }
}

@Test func playbackAudibleTimingUsesTheDeviceAndRejectsPreviousPlaybackCallbacks() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device })
  let id = UUID()
  let times = Mutex<[TimeInterval]>([])
  let receive: @Sendable (SpeechPlaybackUpdate) -> Void = { update in
    if case .milestone(.audibleOutput(let time)) = update { times.withLock { $0.append(time) } }
  }
  let audio = try SynthesizedAudio(samples: [0.1], sampleRate: 24_000)
  await playback.start(id: id, receive: receive)
  try await playback.enqueue(audio, id: id)
  #expect(times.withLock { $0.isEmpty })
  let old = try #require(device.audible.withLock { $0 })
  await playback.stop(id: id)
  await playback.start(id: id, receive: receive)
  try await playback.enqueue(audio, id: id)
  old(100)
  let current = try #require(device.audible.withLock { $0 })
  current(200)
  for _ in 0..<100 {
    if !times.withLock({ $0.isEmpty }) { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(times.withLock { $0 } == [200])
  await playback.stop(id: id)
}

@Test func playbackBackpressureStopsProducersUntilSamplesPlay() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device })
  let id = UUID()
  await playback.start(id: id) { _ in }
  let audio = try SynthesizedAudio(samples: Array(repeating: 0.1, count: 4_096), sampleRate: 8_000)
  try await playback.enqueue(audio, id: id)
  let completed = Mutex(false)
  let waiting = Task {
    try await playback.enqueue(audio, id: id)
    completed.withLock { $0 = true }
  }
  try await Task.sleep(for: .milliseconds(30))
  #expect(!completed.withLock { $0 })
  #expect(device.completions.withLock { $0.count } == 1)
  let first = try #require(device.completions.withLock { $0.first })
  first()
  try await waiting.value
  #expect(device.completions.withLock { $0.count } == 2)
  await playback.stop(id: id)
}

@Test func playbackCancellationReleasesWaitersAndIgnoresOldDeviceCallbacks() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device })
  let id = UUID()
  let audio = try SynthesizedAudio(samples: Array(repeating: 0.1, count: 4_096), sampleRate: 8_000)
  await playback.start(id: id) { _ in }
  try await playback.enqueue(audio, id: id)
  let waiting = Task { try await playback.enqueue(audio, id: id) }
  try await Task.sleep(for: .milliseconds(20))
  waiting.cancel()
  await #expect(throws: CancellationError.self) { try await waiting.value }
  let old = try #require(device.completions.withLock { $0.first })
  await playback.start(id: id) { _ in }
  try await playback.enqueue(audio, id: id)
  let finished = Mutex(false)
  let finishing = Task {
    try await playback.finish(id: id)
    finished.withLock { $0 = true }
  }
  old()
  try await Task.sleep(for: .milliseconds(20))
  #expect(!finished.withLock { $0 })
  let current = try #require(device.completions.withLock { $0.last })
  current()
  try await finishing.value
  #expect(finished.withLock { $0 })
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_NATIVE_PLAYBACK_CHECK"] == "1"))
func playbackRenderReferenceUsesTheDeviceClockAndStopsWithOutput() async throws {
  struct RenderProbe {
    var frames = 0
    var samples = 0
    var valid = true
    var maximumDuration = 0.0
    var maximumArrivalDelay = -Double.infinity
  }
  let probe = Mutex(RenderProbe())
  let started = ProcessInfo.processInfo.systemUptime
  let playback = VoicePlayback(reference: { frame in
    probe.withLock {
      $0.frames += 1
      $0.samples += frame.samples.count
      $0.maximumDuration = max($0.maximumDuration, Double(frame.samples.count) / frame.sampleRate)
      $0.maximumArrivalDelay = max(
        $0.maximumArrivalDelay, ProcessInfo.processInfo.systemUptime - frame.startTime)
      $0.valid =
        $0.valid && frame.startTime.isFinite && frame.startTime >= started - 1
        && frame.startTime <= ProcessInfo.processInfo.systemUptime + 2
        && frame.sampleRate > 0 && frame.samples.allSatisfy(\.isFinite)
    }
  })
  let id = UUID()
  await playback.start(id: id) { _ in }
  // Exercise the hardware renderer without an audible sound or microphone access.
  let audio = try SynthesizedAudio(samples: Array(repeating: 0, count: 4_096), sampleRate: 16_000)
  try await playback.enqueue(audio, id: id)
  try await playback.finish(id: id)
  #expect(probe.withLock { $0.valid && $0.frames > 0 && $0.samples > 0 })
  print("DEVICE ECHO REFERENCE: \(probe.withLock { $0 })")
  try await Task.sleep(for: .milliseconds(20))
  let framesAfterStop = probe.withLock { $0.frames }
  try await Task.sleep(for: .milliseconds(50))
  #expect(probe.withLock { $0.frames } == framesAfterStop)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_NATIVE_PLAYBACK_CHECK"] == "1"))
func playbackEchoReferenceIncludesUtterancesShorterThanATapBatch() async throws {
  let samples = Mutex(0)
  let playback = VoicePlayback(reference: { frame in samples.withLock { $0 += frame.samples.count }
  })
  let id = UUID()
  await playback.start(id: id) { _ in }
  // Forty milliseconds must have a reference even though a node tap batches at least 100 ms.
  try await playback.enqueue(
    .init(samples: [Float](repeating: 0, count: 640), sampleRate: 16_000), id: id)
  try await playback.finish(id: id)
  #expect(samples.withLock { $0 } > 0)
}

@Test func spokenPhraseCompletionWaitsForHardwareAndIgnoresDuplicateCallbacks() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device })
  let id = UUID()
  let phrases = Mutex<[String]>([])
  await playback.start(id: id) { update in
    if case .utteranceFinished(let phrase) = update { phrases.withLock { $0.append(phrase) } }
  }
  let audio = try SynthesizedAudio(samples: [0.1, 0.2], sampleRate: 24_000)
  try await playback.enqueue(audio, id: id)
  try await playback.markUtterance("First.", id: id)
  try await playback.enqueue(audio, id: id)
  try await playback.markUtterance("Second.", id: id)
  let callbacks = device.completions.withLock { $0 }
  #expect(phrases.withLock { $0.isEmpty })
  callbacks[1]()  // Executor delivery can be reordered even when the hardware plays in order.
  try await Task.sleep(for: .milliseconds(10))
  #expect(phrases.withLock { $0.isEmpty })
  callbacks[0]()
  for _ in 0..<100 {
    if phrases.withLock({ $0.count == 2 }) { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  callbacks[0]()
  #expect(phrases.withLock { $0 } == ["First.", "Second."])
  try await playback.finish(id: id)
  await playback.start(id: id) { _ in
    Issue.record("An old completion reached a new playback session")
  }
  callbacks[1]()
  try await Task.sleep(for: .milliseconds(10))
}

@Test func playbackDeviceChangeReleasesWaitersWithoutMarkingUnheardTextAsSpoken() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device })
  let id = UUID()
  let spoken = Mutex<[String]>([])
  await playback.start(id: id) { update in
    if case .utteranceFinished(let text) = update { spoken.withLock { $0.append(text) } }
  }
  try await playback.enqueue(.init(samples: [0.1, 0.2], sampleRate: 24_000), id: id)
  try await playback.markUtterance("Still pending.", id: id)
  let draining = Task { try await playback.finish(id: id) }
  let interrupt = try #require(device.interruption.withLock { $0 })
  interrupt()
  await #expect(throws: TTSError.self) { try await draining.value }
  let completion = try #require(device.completions.withLock { $0.first })
  completion()
  #expect(spoken.withLock { $0.isEmpty })
  let next = UUID()
  await playback.start(id: next) { _ in }
  interrupt()
  try await playback.enqueue(.init(samples: [0.1], sampleRate: 24_000), id: next)
  await playback.stop(id: next)
}

@Test func playbackWatchdogRecoversWhenADeviceNeverCompletesItsBuffer() async throws {
  let device = OutputProbe()
  let playback = VoicePlayback(makeDevice: { device }, stallTimeout: .milliseconds(30))
  let id = UUID()
  await playback.start(id: id) { _ in }
  try await playback.enqueue(.init(samples: [0.1], sampleRate: 24_000), id: id)
  await #expect(throws: TTSError.self) { try await playback.finish(id: id) }
  #expect(device.stopCount.withLock { $0 } == 1)
  await #expect(throws: TTSError.self) {
    try await playback.enqueue(.init(samples: [0.1], sampleRate: 24_000), id: id)
  }
}
