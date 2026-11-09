import AVFoundation
import Foundation
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesAudio

@Test func speechDiskBacklogRetiresPagesAndClosesItsPrivateFiles() async throws {
  try await Task.detached {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { removeSpeechTestDirectory(directory) }
    let store = DiskSpeechAudioStore(directory: directory, maximumPendingBytes: 128_000 * 4)
    let samples = (0..<128_000).map { Float($0) / 128_000 }
    try store.append(samples)
    #expect(store.endSample == 128_000)
    #expect(try store.read(from: 63_990, maximumSamples: 100) == Array(samples[63_990..<64_000]))
    #expect(try store.read(from: 64_000, maximumSamples: 100) == Array(samples[64_000..<64_100]))
    #expect(throws: SpeechError.self) { try store.append([0.1]) }
    try store.retire(before: 64_000)
    try store.append(Array(repeating: 0.5, count: 64_000))
    #expect(store.endSample == 192_000)
    #expect(try store.read(from: 0, maximumSamples: 10).isEmpty)
    let leaf = try #require(
      FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let permissions =
      try FileManager.default.attributesOfItem(atPath: leaf.path)[.posixPermissions] as? Int
    #expect(permissions == 0o700)
    try store.close()
    try store.close()
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    #expect(throws: CancellationError.self) { try store.append([0.1]) }
  }.value
}

@Test func speechDiskBacklogReportsWriteFailureAndCanStillClose() async throws {
  try await Task.detached {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { removeSpeechTestDirectory(directory) }
    try Data([0]).write(to: directory)
    let store = DiskSpeechAudioStore(directory: directory)
    #expect(throws: (any Error).self) { try store.append([0.1]) }
    #expect(store.endSample == 0)
    try store.close()
  }.value
}

private enum RecoveryScenario: CaseIterable, Sendable { case busy, temporary, trailingSilence }

@Test(arguments: RecoveryScenario.allCases)
private func speechRecognitionRetriesAndDrainsMoreThanTheMemoryWindowWithoutMissingWords(
  _ scenario: RecoveryScenario
)
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeSpeechTestDirectory(directory) }
  let engine = RecoveringWindowEngine(scenario: scenario)
  let phrases = Mutex<[SpeechPhrase]>([])
  let recovery = Mutex<[SpeechRecoveryUpdate.Phase]>([])
  let (completed, completion) = AsyncStream<Void>.makeStream()
  var request = SpeechChannelRequest(
    language: .automatic,
    output: { phrase in phrases.withLock { $0.append(phrase) } },
    failure: { _ in Issue.record("A transient failure must recover.") })
  request.audioBackingStore = DiskSpeechAudioStore(directory: directory)
  let channel = try WindowSpeechChannel(engine: engine, request: request)
  channel.onRecovery { update in recovery.withLock { $0.append(update.phase) } }
  defer { channel.cancel() }
  try await appendSpeechSeconds(3, to: channel)
  var starts = engine.started.makeAsyncIterator()
  _ = await starts.next()
  try await appendSpeechSeconds(45, to: channel, amplitude: scenario == .trailingSilence ? 0 : 0.1)
  channel.finish { completion.yield(()) }
  engine.release()
  var results = completed.makeAsyncIterator()
  _ = await results.next()
  let finalWords = phrases.withLock { $0.filter(\.isFinal).flatMap(\.words).map(\.text) }
  let expectedWords = scenario == .trailingSilence ? 3 : 48
  #expect(finalWords == (0..<expectedWords).map { "word-\($0)" })
  #expect(
    recovery.withLock {
      $0.contains(.retrying) && $0.contains(.catchingUp) && $0.contains(.caughtUp)
    })
  #expect(await engine.firstWindowWasRetried)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  completion.finish()
}

@Test func speechRecognitionCancellationWhileRetryingStopsAndCleansBacklog() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeSpeechTestDirectory(directory) }
  let (recoveries, recovered) = AsyncStream<SpeechRecoveryUpdate>.makeStream()
  let (finishes, finished) = AsyncStream<Void>.makeStream()
  var request = SpeechChannelRequest(
    language: .automatic,
    output: { _ in Issue.record("Cancelled inference must not publish words.") },
    failure: { _ in Issue.record("Cancellation is not a recognition failure.") })
  request.audioBackingStore = DiskSpeechAudioStore(directory: directory)
  let channel = try WindowSpeechChannel(engine: OverloadedRecoveryEngine(), request: request)
  channel.onRecovery { recovered.yield($0) }
  try await appendSpeechSeconds(3, to: channel)
  var events = recoveries.makeAsyncIterator()
  #expect(await events.next()?.phase == .retrying)
  channel.cancel()
  channel.finish { finished.yield(()) }
  var completions = finishes.makeAsyncIterator()
  _ = await completions.next()
  #expect(await events.next()?.phase == .stopped)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  recovered.finish()
  finished.finish()
}

private func appendSpeechSeconds(
  _ seconds: Int, to channel: WindowSpeechChannel, amplitude: Float = 0.1
) async throws {
  try await Task.detached {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    buffer.frameLength = 16_000
    let samples = try #require(buffer.floatChannelData?[0])
    for index in 0..<16_000 { samples[index] = amplitude }
    for _ in 0..<seconds { channel.append(buffer) }
  }.value
}

private actor RecoveringWindowEngine: SpeechWindowEngine {
  nonisolated let started: AsyncStream<Void>
  private let start: AsyncStream<Void>.Continuation
  private let releases: AsyncStream<Void>
  private nonisolated let released: AsyncStream<Void>.Continuation
  private var firstWindow: SpeechWindowPosition?
  private(set) var firstWindowWasRetried = false
  private var attempts = 0
  private let scenario: RecoveryScenario
  init(scenario: RecoveryScenario) {
    self.scenario = scenario
    (started, start) = AsyncStream.makeStream()
    (releases, released) = AsyncStream.makeStream()
  }
  nonisolated func release() {
    released.yield(())
    released.finish()
  }
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    attempts += 1
    if attempts == 1 {
      firstWindow = request.window
      start.yield(())
      for await _ in releases { break }
      if scenario == .temporary { throw SpeechError.unavailable("Transient fixture error") }
      throw SpeechError.overloaded
    }
    if attempts == 2 { firstWindowWasRetried = request.window?.start == firstWindow?.start }
    let start = request.window?.start ?? 0
    let end = start + Double(request.samples.count) / 16_000
    let words = (Int(ceil(start))..<Int(ceil(end))).compactMap { second -> SpeechWord? in
      if scenario == .trailingSilence, second >= 3 { return nil }
      guard Double(second) + 0.6 <= end else { return nil }
      return .init(
        text: "word-\(second)", start: Double(second) - start,
        end: Double(second) + 0.6 - start)
    }
    return .init(words: words)
  }
}

private struct OverloadedRecoveryEngine: SpeechWindowEngine {
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    throw SpeechError.overloaded
  }
}

private func removeSpeechTestDirectory(_ directory: URL) {
  guard FileManager.default.fileExists(atPath: directory.path) else { return }
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Could not remove the speech fixture directory.")
  }
}
