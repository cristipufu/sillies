import AVFoundation
import AppKit
import SilliesAudioTestSupport
import SilliesCore
import SilliesModelStore
import SilliesPersistence
import SilliesReasoning
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesAudio

private final class FixtureAudioCapture: SessionAudioCapture, Sendable {
  let finishes = Mutex(0)
  private let update: @Sendable (AudioCaptureUpdate) -> Void
  private let queue = DispatchQueue(label: "sillies.test.capture")
  private let failure: SessionFailure?
  init(failure: SessionFailure? = nil, update: @escaping @Sendable (AudioCaptureUpdate) -> Void) {
    self.failure = failure
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
  func recover(_ update: SpeechRecoveryUpdate) { self.update(.transcriptionRecovery(update)) }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    finishes.withLock { $0 += 1 }
    queue.asyncAfter(deadline: .now() + 0.02) {
      completion(
        AudioCaptureResult(
          transcript: "Please ship the report on Friday.", recordingURL: nil, duration: 4,
          failure: self.failure))
    }
  }
}

@Test(arguments: [CompanionSkillKind.listen, .participate, .record])
@MainActor func unavailableNotesDoNotInterruptDownloadedTranscription(_ kind: CompanionSkillKind)
  async throws
{
  let speechModel = try SpeechModelCatalog.bundled().manifest(for: "parakeet-ultra").model
  let captures = Mutex<[AudioCaptureConfiguration]>([])
  let unavailable = Mutex(true)
  let reasoning = FixtureReasoning(availability: { language in
    language == fixtureFrench.id && unavailable.withLock { $0 }
      ? "The selected text model does not support this language." : nil
  })
  var languages = fixtureAudioLanguages()
  languages.preferences.remember(fixtureEnglish, for: speechModel)
  languages.load = {
    SpeechLanguageCatalog(languages: [fixtureEnglish, fixtureFrench], model: speechModel)
  }
  let session = AudioSkillSession(
    request: .init(
      kind: kind, target: nil, recordingDirectory: FileManager.default.temporaryDirectory),
    services: .init(
      captureFactory: { configuration, update in
        captures.withLock { $0.append(configuration) }
        return FixtureAudioCapture(update: update)
      }, languages: languages, reasoning: reasoning,
      makeCallSpeakerReader: { UnavailableCallSpeakerReader() }), onChange: {})
  defer { session.cancel() }
  let model = session.presentation
  session.start()
  try await waitForAudioCondition {
    model.phase == .capturing && model.reasoningAvailability.isAvailable
  }
  model.onSelectLanguage?(fixtureFrench.id)
  try await waitForAudioCondition { model.reasoningAvailability.failureMessage != nil }
  #expect(model.selectedLanguageID == fixtureFrench.id)
  #expect(model.phase == .capturing)
  #expect(model.transcriptionFailure == nil)
  #expect(model.canPause && model.canSelectLanguage)
  #expect(model.transcript.contains("report"))
  #expect(model.model.id == speechModel.id)

  var openedSettings = false
  let controller = AudioSessionWindowController(appearance: ThemeEnvironment()) {
    openedSettings = true
  }
  defer { controller.close() }
  controller.prepare(model)
  model.onOpenTextModelSettings?()
  #expect(openedSettings)
  unavailable.withLock { $0 = false }
  controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
  try await waitForAudioCondition { model.reasoningAvailability.isAvailable }
  #expect(model.phase == .capturing && model.transcript.contains("report"))
  #expect(captures.withLock { $0.count == 1 && $0.first?.model.id == speechModel.id })
  session.cancel()
  model.onRefreshReasoningAvailability?()
  #expect(
    model.reasoningAvailability.isAvailable, "A closed capture must not restart availability work.")
}

@MainActor private func waitForAudioCondition(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(condition(), "The fixture audio session did not reach the expected state.")
}

@Test(arguments: [CompanionSkillKind.listen, .participate, .record])
@MainActor func audioSkillsRetainPreparationFailuresWhenFinishing(_ kind: CompanionSkillKind)
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let failure = SessionFailure(category: .transcription, message: "Synthetic model unavailable")
  var languages = fixtureAudioLanguages()
  languages.load = { throw failure }
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(
    vault: vault,
    audioFactory: { _, update in
      Issue.record("Model preparation failed; capture must not start.")
      return FixtureAudioCapture(update: update)
    }, audioLanguages: languages)
  let target = WindowTargetCandidate(
    windowID: 321, processID: 123, appName: "Synthetic meeting",
    frame: CGRect(x: 100, y: 100, width: 700, height: 500))
  coordinator.startSkill(kind, for: "mochi", companionName: "Mochi", target: target)
  let presentation = try #require(coordinator.activeAudioSession)
  try await waitForAudioCondition { presentation.phase == .failed(failure) }
  coordinator.stopSkill(for: "mochi")
  await coordinator.shutdown()
  let id = try #require(vault.records.first?.id)
  let saved = try #require(try await vault.record(id: id))
  #expect(saved.failure == failure)
  #expect(saved.transcript.isEmpty && saved.audioFilename == nil)
  #expect(presentation.phase == .finished)
  #expect(presentation.captureFailure == failure)
  #expect(presentation.reasoningAvailability.statusMessage == nil)
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
  let recordingID = try #require(reloaded.records.first { $0.kind == .record }?.id)
  #expect(try await reloaded.record(id: recordingID)?.transcript.isEmpty == false)
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
  let recordingID = try #require(vault.records.first?.id)
  #expect(
    try await vault.record(id: recordingID)?.transcript.contains("Please ship the report") == true)
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
  func close() { visibility = .closed }
  func snapshot() -> [CGWindowID: WindowTargetSnapshot] {
    [321: WindowTargetSnapshot(frame: frame, title: "Meeting", visibility: visibility)]
  }
}

private enum MeetingCaptureState: CaseIterable { case recording, paused }

@Test(arguments: [CompanionSkillKind.listen, .participate])
@MainActor private func closingMeetingKeepsItsWarningWithTheOriginalCompanion(
  _ kind: CompanionSkillKind
) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let probe = BoundAudioWindowProbe()
  let failure = SessionFailure(category: .audioProcessing, message: "Fixture capture backlog")
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(
    vault: vault,
    audioFactory: { _, update in FixtureAudioCapture(failure: failure, update: update) },
    audioLanguages: fixtureAudioLanguages(), snapshotLoader: { _, _ in await probe.snapshot() })
  var changedCompanions: Set<String> = []
  coordinator.onBindingChanged = { id, _ in changedCompanions.insert(id) }
  let target = WindowTargetCandidate(
    windowID: 321, processID: 123, appName: "Zoom",
    frame: CGRect(x: 100, y: 100, width: 700, height: 500))
  coordinator.startSkill(kind, for: "mochi", companionName: "Mochi", target: target)
  await waitForCapture(coordinator)
  let audioPresentation = try #require(coordinator.activeAudioSession)
  await probe.close()
  coordinator.pollBoundWindows()
  try await waitForAudioCondition {
    if case .completed = coordinator.binding(for: "mochi") { return true }
    return false
  }
  let binding = coordinator.binding(for: "mochi")
  let presentation = coordinator.presentation(for: "mochi")
  #expect(binding.boundTarget == nil)
  #expect(changedCompanions == ["mochi"])
  #expect(coordinator.binding(for: "kiko") == .followingFocusedWindow)
  #expect(coordinator.presentation(for: "kiko").completedRecord == nil)
  let saved = try #require(presentation.completedRecord)
  #expect(saved.characterID == "mochi" && saved.appName == "Zoom")
  #expect(saved.failure == failure)
  #expect(audioPresentation.captureFailure == failure)
  let hud = CompanionHUDModel()
  hud.updatePresentation(presentation)
  #expect(hud.sourceName(for: binding) == "Zoom")
  // An unrelated cached record must never supply the source label.
  hud.completedRecord = SessionRecordHeader(
    SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "kiko", characterName: "Kiko", source: .init(appName: "Microphone"))))
  #expect(hud.sourceName(for: binding) == String(localized: "Meeting"))
  await coordinator.shutdown()
}

@Test(arguments: [CompanionSkillKind.listen, .participate], MeetingCaptureState.allCases)
@MainActor private func closingTheBoundMeetingFinishesCaptureOnceAndReleasesTheCompanion(
  _ kind: CompanionSkillKind, _ state: MeetingCaptureState
) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let probe = BoundAudioWindowProbe()
  let capture = Mutex<FixtureAudioCapture?>(nil)
  let vault = SessionVaultStore(
    directory: directory, notesGenerator: { _ in LocalNotes(summary: "Fixture", actions: []) })
  let coordinator = SkillCoordinator(
    vault: vault,
    audioFactory: { _, update in
      let fixture = FixtureAudioCapture(
        failure: .init(category: .captureInterrupted, message: "Application stream ended"),
        update: update)
      capture.withLock { $0 = fixture }
      return fixture
    }, audioLanguages: fixtureAudioLanguages(),
    snapshotLoader: { _, _ in await probe.snapshot() })
  let target = WindowTargetCandidate(
    windowID: 321, processID: 123, appName: "Meeting", windowTitle: "Project review",
    frame: CGRect(x: 100, y: 100, width: 700, height: 500))
  coordinator.startSkill(kind, for: "mochi", companionName: "Mochi", target: target)
  await waitForCapture(coordinator)
  if state == .paused { coordinator.activeAudioSession?.onPause?() }
  await probe.close()
  coordinator.pollBoundWindows()
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while coordinator.activeAudioSession != nil, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
    coordinator.pollBoundWindows()
  }
  #expect(coordinator.activeAudioSession == nil)
  #expect(!coordinator.binding(for: "mochi").isBound)
  let fixture = try #require(capture.withLock { $0 })
  #expect(fixture.finishes.withLock { $0 } == 1)
  await vault.flush()
  #expect(vault.records.count == 1)
  let saved = try #require(vault.records.first)
  #expect(saved.kind == kind && saved.appName == "Meeting" && saved.windowTitle == "Project review")
  #expect(saved.failure == nil)
  #expect(try await vault.record(id: saved.id)?.transcript == "Please ship the report on Friday.")
  #expect(!coordinator.binding(for: "mochi").isBound)
  await coordinator.shutdown()
}

@Test @MainActor func audioRecoveryStatusWaitsForBothSourcesAndSurvivesPause() async throws {
  let capture = Mutex<FixtureAudioCapture?>(nil)
  let session = AudioSkillSession(
    request: .init(
      kind: .listen, target: nil, recordingDirectory: FileManager.default.temporaryDirectory),
    services: .init(
      captureFactory: { _, update in
        let fixture = FixtureAudioCapture(update: update)
        capture.withLock { $0 = fixture }
        return fixture
      }, languages: fixtureAudioLanguages(), reasoning: FixtureReasoning(),
      makeCallSpeakerReader: { UnavailableCallSpeakerReader() }), onChange: {})
  defer { session.cancel() }
  session.start()
  let model = session.presentation
  try await waitForAudioCondition { model.phase == .capturing }
  let fixture = try #require(capture.withLock { $0 })
  let application = UUID()
  let microphone = UUID()
  fixture.recover(.init(channel: application, phase: .catchingUp, queuedSeconds: 30))
  fixture.recover(.init(channel: microphone, phase: .retrying, queuedSeconds: 2))
  try await waitForAudioCondition { model.isRecoveringTranscription }
  fixture.recover(.init(channel: application, phase: .caughtUp, queuedSeconds: 0))
  model.onPause?()
  try await waitForAudioCondition { model.phase == .paused }
  #expect(model.isRecoveringTranscription)
  #expect(model.status == String(localized: "Paused"))
  model.onResume?()
  #expect(model.status == String(localized: "Transcription is catching up. Recording continues."))
  fixture.recover(.init(channel: microphone, phase: .caughtUp, queuedSeconds: 0))
  try await waitForAudioCondition { !model.isRecoveringTranscription }
  #expect(model.status == String(localized: "Transcribing"))
  #expect(model.transcriptionFailure == nil)
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
