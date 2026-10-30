import AVFoundation
import AppKit
import SilliesAudioTestSupport
import SilliesCore
import Testing

@testable import SilliesApp
@testable import SilliesAudio

private final class FixtureAudioCapture: SessionAudioCapture, @unchecked Sendable {
  private let update: @Sendable (AudioCaptureUpdate) -> Void
  private let queue = DispatchQueue(label: "sillies.test.capture")
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) {
    self.update = update
  }
  func start() {
    update(.capturing("Fixture microphone"))
    update(
      .transcript(
        "[00:00] You · microphone: Please ship the report on Friday.", level: 0.2, elapsed: 4))
  }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) { update(.languageChanged(language)) }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    queue.asyncAfter(deadline: .now() + 0.02) {
      completion(
        AudioCaptureResult(
          transcript: "Please ship the report on Friday.", recordingURL: nil, duration: 4,
          error: nil))
    }
  }
}

@Test func audioModesCaptureTheIntendedSources() {
  let listen = AudioCaptureConfiguration(kind: .listen, target: nil, recordingURL: nil)
  let participate = AudioCaptureConfiguration(kind: .participate, target: nil, recordingURL: nil)
  let record = AudioCaptureConfiguration(kind: .record, target: nil, recordingURL: nil)
  #expect(listen.sources == [.application, .microphone])
  #expect(participate.sources == [.application, .microphone])
  #expect(record.sources == [.microphone])
}

@Test(arguments: [CompanionSkillKind.listen, .participate, .record])
@MainActor func audioSkillsStartWithoutOpeningTheTranscriptWindow(_ kind: CompanionSkillKind)
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(
    directory: directory, notesGenerator: { _ in LocalNotes(summary: "Fixture", actions: []) })
  let coordinator = SkillCoordinator(
    vault: vault, audioFactory: { _, update in FixtureAudioCapture(update: update) },
    audioLanguages: fixtureAudioLanguages())
  var opened = 0
  coordinator.onOpenAudioSession = { _ in opened += 1 }
  let target = WindowTargetCandidate(
    windowID: 123, processID: 321, appName: "Fixture meeting",
    frame: CGRect(x: 100, y: 100, width: 800, height: 600))
  coordinator.startSkill(kind, for: "mochi", companionName: "Mochi", target: target)
  await waitForCapture(coordinator)
  #expect(opened == 0)
  let session = try #require(coordinator.activeAudioSession)
  coordinator.startSkill(kind, for: "kiko", companionName: "Kiko", target: target)
  #expect(opened == 0)
  coordinator.onOpenAudioSession?(session)
  #expect(opened == 1)
  session.onPause?()
  session.onSelectLanguage?(fixtureFrench.id)
  for _ in 0..<300 {
    if session.pendingLanguageID == nil { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(session.selectedLanguageID == fixtureFrench.id)
  #expect(session.phase == .paused)
  #expect(session.transcript.contains("report"))
  #expect(opened == 1)
  await coordinator.shutdown()
}

@Test @MainActor func microphoneSessionSurvivesMetadataTicksAndFlushesAsynchronously() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(
    directory: directory, notesGenerator: { _ in LocalNotes(summary: "Fixture notes", actions: []) }
  )
  let coordinator = SkillCoordinator(
    vault: vault, audioFactory: { _, update in FixtureAudioCapture(update: update) },
    audioLanguages: fixtureAudioLanguages())
  coordinator.startSkill(.record, for: "mochi", companionName: "Mochi")
  await waitForCapture(coordinator)
  #expect(!coordinator.binding(for: "mochi").isBound)
  #expect(coordinator.binding(for: "mochi").hasPresentation)
  coordinator.pollBoundWindows()
  #expect(coordinator.activeAudioSession != nil)
  coordinator.startSkill(.record, for: "kiko", companionName: "Kiko")
  #expect(coordinator.binding(for: "kiko") == .followingFocusedWindow)
  coordinator.recordStash(
    items: ["keep this"], for: "mochi", companionName: "Mochi", currentTarget: nil)
  #expect(coordinator.activeAudioSession != nil)
  coordinator.stopSkill(for: "mochi")
  #expect(vault.records.filter { $0.kind == .record }.isEmpty)
  #expect(coordinator.activeAudioSession != nil)
  await coordinator.shutdown()
  let reloaded = SessionVaultStore(directory: directory)
  await reloaded.waitUntilLoaded()
  #expect(reloaded.records.contains { $0.kind == .record && !$0.transcript.isEmpty })
  #expect(reloaded.records.contains { $0.kind == .stash })
  reloaded.cancelPendingSummaries()
  await reloaded.flush()
}

@Test @MainActor func microphoneFinishCompletesInsideTerminationModalRunLoop() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(
    vault: vault, audioFactory: { _, update in FixtureAudioCapture(update: update) },
    audioLanguages: fixtureAudioLanguages())
  coordinator.startSkill(.record, for: "mochi", companionName: "Mochi")
  await waitForCapture(coordinator)
  #expect(coordinator.activeAudioSession?.phase == .capturing)
  var finished = false
  coordinator.flushForTermination { MainActor.assumeIsolated { finished = true } }
  pumpTerminationRunLoop { finished }
  #expect(finished)
  let data = try Data(contentsOf: directory.appendingPathComponent("sessions.json"))
  #expect(String(decoding: data, as: UTF8.self).contains("Please ship the report"))
}

@MainActor private func pumpTerminationRunLoop(until finished: () -> Bool) {
  let deadline = Date().addingTimeInterval(3)
  while !finished() && Date() < deadline {
    _ = RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.01))
  }
}

@MainActor private func waitForCapture(_ coordinator: SkillCoordinator) async {
  for _ in 0..<300 {
    if coordinator.activeAudioSession?.phase == .capturing { return }
    try? await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("The fixture capture did not start.")
}

@Test func recordingWriterClosesAPlayableAACFile() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let url = directory.appendingPathComponent("recording.m4a")
  let duration = try await Task.detached {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    let channels = try #require(buffer.floatChannelData)
    for channel in 0..<2 {
      for index in 0..<44_100 {
        channels[channel][index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * 0.1)
      }
    }
    let writer = try AudioRecordingWriter(destination: url)
    try writer.append(buffer)
    #expect(try writer.finish() == url)
    let saved = try AVAudioFile(forReading: url)
    #expect(saved.length > 0)
    let decoded = try #require(
      AVAudioPCMBuffer(pcmFormat: saved.processingFormat, frameCapacity: 1_024))
    try saved.read(into: decoded)
    #expect(decoded.frameLength > 0)
    return Double(saved.length) / saved.processingFormat.sampleRate
  }.value
  #expect(abs(duration - 1) < 0.1)
  #expect(
    !FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("recording.partial.m4a").path))
}

private actor BoundAudioWindowProbe {
  var visibility = WindowTargetSnapshot.Visibility.visible
  let frame = CGRect(x: 100, y: 100, width: 700, height: 500)
  func hide() { visibility = .hidden }
  func show() { visibility = .visible }
  func snapshot() -> [CGWindowID: WindowTargetSnapshot] {
    [321: WindowTargetSnapshot(frame: frame, title: "Meeting", visibility: visibility)]
  }
}

@Test @MainActor func hiddenMeetingWindowKeepsCaptureAndBindingUntilItReturns() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let probe = BoundAudioWindowProbe()
  let vault = SessionVaultStore(
    directory: directory, notesGenerator: { _ in LocalNotes(summary: "Fixture", actions: []) })
  let coordinator = SkillCoordinator(
    vault: vault,
    audioFactory: { _, update in FixtureAudioCapture(update: update) },
    audioLanguages: fixtureAudioLanguages(), snapshotLoader: { _, _ in await probe.snapshot() })
  let target = WindowTargetCandidate(
    windowID: 321, processID: 123, appName: "Meeting",
    frame: CGRect(x: 100, y: 100, width: 700, height: 500))
  coordinator.startSkill(.listen, for: "mochi", companionName: "Mochi", target: target)
  await waitForCapture(coordinator)
  await probe.hide()
  coordinator.pollBoundWindows()
  for _ in 0..<300 {
    if coordinator.binding(for: "mochi").boundTarget?.isVisible == false { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(coordinator.binding(for: "mochi").boundTarget?.isVisible == false)
  #expect(coordinator.activeAudioSession?.phase == .capturing)
  #expect(vault.records.isEmpty)
  await probe.show()
  coordinator.pollBoundWindows()
  for _ in 0..<300 {
    if coordinator.binding(for: "mochi").boundTarget?.isVisible == true { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(coordinator.binding(for: "mochi").boundTarget?.windowID == target.windowID)
  #expect(coordinator.binding(for: "mochi").boundTarget?.isVisible == true)
  #expect(coordinator.activeAudioSession?.phase == .capturing)
  await coordinator.shutdown()
}
