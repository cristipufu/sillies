import Foundation
import SilliesTTS
import SilliesVoicePlayback
import Synchronization
import Testing

private final class OutputProbe: VoiceOutputDevice, Sendable {
  let completions = Mutex<[@Sendable () -> Void]>([])
  let stopCount = Mutex(0)
  func schedule(_ audio: SynthesizedAudio, completed: @escaping @Sendable () -> Void) throws {
    completions.withLock { $0.append(completed) }
  }
  func stop() { stopCount.withLock { $0 += 1 } }
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
  }
  let probe = Mutex(RenderProbe())
  let started = ProcessInfo.processInfo.systemUptime
  let playback = VoicePlayback(reference: { frame in
    probe.withLock {
      $0.frames += 1
      $0.samples += frame.samples.count
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
  try await Task.sleep(for: .milliseconds(20))
  let framesAfterStop = probe.withLock { $0.frames }
  try await Task.sleep(for: .milliseconds(50))
  #expect(probe.withLock { $0.frames } == framesAfterStop)
}
