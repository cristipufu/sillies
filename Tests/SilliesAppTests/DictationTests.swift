import AppKit
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesWriting
import SwiftUI
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesAudio

private final class DictationCaptureFixture: SessionAudioCapture, Sendable {
  let update: @Sendable (AudioCaptureUpdate) -> Void
  let text: String
  init(text: String, update: @escaping @Sendable (AudioCaptureUpdate) -> Void) {
    self.text = text
    self.update = update
  }
  func start() {
    update(.capturing("Microphone"))
    update(.transcript(text, level: 0.2, elapsed: 2))
  }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    var result = AudioCaptureResult(
      transcript: "[00:00] You: \(text)", recordingURL: nil, duration: 2, failure: nil)
    result.segments = [.init(sequence: 0, source: "You", start: 0, end: 2, text: text)]
    completion(result)
  }
}

private actor DictationInsertionFixture: TextInserting {
  var inserted: [String] = []
  var changed = false
  var selection = ""
  var permissionGranted = true
  func denyPermission() { permissionGranted = false }
  func select(_ text: String) { selection = text }
  func changeFocus() { changed = true }
  func capture(_ application: FrontmostApplication) throws -> TextDestination {
    if !permissionGranted { throw TextAccessError.permission }
    return .init(
      id: UUID(), application: application, selection: selection)
  }
  func insert(_ text: String, into destination: TextDestination) throws {
    if changed { throw TextAccessError.changed }
    inserted.append(text)
  }
  func release(_ destination: TextDestination) {}
}

private actor CleanupFixture {
  var continuation: CheckedContinuation<String, Never>?
  func run() async -> String { await withCheckedContinuation { continuation = $0 } }
  func complete() {
    continuation?.resume(returning: "A late, different answer")
    continuation = nil
  }
}

@MainActor private struct DictationFixture {
  let model: DictationCoordinator
  let history: WritingHistory
  var currentApplication: () -> FrontmostApplication? {
    { .init(processID: 42, name: "Editor", bundleIdentifier: "test.editor") }
  }
  let insertion = DictationInsertionFixture()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let domain = "sillies-dictation-tests-\(UUID())"
  let defaults: UserDefaults
  init(
    text: String = "Ștefan, deploy API_v2 at 16:30.",
    transform: @escaping BoundedTextCleanup.Transform = { $0 }
  ) throws {
    defaults = try #require(UserDefaults(suiteName: domain))
    let preferences = DictationPreferences(defaults: defaults)
    preferences.languageIdentifier = "en-US"
    let languages = AudioLanguageEnvironment(
      preferences: SpeechLanguagePreferences(defaults: defaults),
      load: {
        SpeechLanguageCatalog(languages: [.init(id: "en-US", name: "English", isInstalled: true)])
      })
    history = WritingHistory(directory: directory)
    model = DictationCoordinator(
      services: .init(
        capture: .init(
          factory: { _, update in DictationCaptureFixture(text: text, update: update) },
          loadLanguages: { try await languages.load() },
          deliver: { MainRunLoopDelivery.perform($0) }),
        text: .init(
          insertion: insertion, cleanup: BoundedTextCleanup(),
          transform: { source, _ in try await transform(source) }),
        context: .init(
          currentApplication: {
            .init(processID: 42, name: "Editor", bundleIdentifier: "test.editor")
          }, vocabularyHints: { [] })),
      preferences: preferences, history: history)
  }

  func finish() async {
    model.cancel()
    await history.flush()
    defaults.removePersistentDomain(forName: domain)
    removeTestFile(at: directory)
  }
}

@MainActor private func waitForDictation(_ condition: () -> Bool) async throws {
  for _ in 0..<400 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(condition(), "Dictation did not reach the expected state")
}

@Test @MainActor func dictationInsertsFinalTextOnceAndIgnoresLateCleanup() async throws {
  let cleanup = CleanupFixture()
  let fixture = try DictationFixture(transform: { _ in await cleanup.run() })
  fixture.model.start(.hold)
  try await waitForDictation { fixture.model.canFinish }
  fixture.model.releaseHold()
  fixture.model.releaseHold()
  try await waitForDictation { fixture.model.result != nil }
  #expect(await fixture.insertion.inserted == ["Ștefan, deploy API_v2 at 16:30."])
  #expect(fixture.model.result?.delivery == .inserted)
  #expect(fixture.model.releaseToInsertion != nil)
  await cleanup.complete()
  try await Task.sleep(for: .milliseconds(30))
  #expect(await fixture.insertion.inserted.count == 1)
  #expect(fixture.history.results.count == 1)
  await fixture.finish()
}

@Test @MainActor func dictationKeepsResultsWhenFocusChanges() async throws {
  let fixture = try DictationFixture()
  fixture.model.toggle()
  try await waitForDictation { fixture.model.canFinish }
  await fixture.insertion.changeFocus()
  fixture.model.toggle()
  try await waitForDictation { fixture.model.result != nil }
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(fixture.model.result?.delivery == .needsPaste)
  #expect(fixture.history.results.first?.text.contains("Ștefan") == true)
  await fixture.finish()
}

@Test @MainActor func dictationReleaseBeforePreparationNeverStartsCapture() async throws {
  let fixture = try DictationFixture()
  fixture.model.start(.hold)
  fixture.model.releaseHold()
  try await Task.sleep(for: .milliseconds(50))
  #expect(!fixture.model.isBusy)
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(fixture.history.results.isEmpty)
  await fixture.finish()
}

@Test @MainActor func clipboardPastePreservesRepresentationsAndNewerCopies() async throws {
  let name = NSPasteboard.Name("sillies-paste-tests-\(UUID())")
  let board = NSPasteboard(name: name)
  defer { board.releaseGlobally() }
  let first = NSPasteboardItem()
  first.setString("original", forType: .string)
  first.setData(Data([1, 2, 3]), forType: .init("test.binary"))
  let second = NSPasteboardItem()
  second.setString("second", forType: .string)
  board.writeObjects([first, second])
  let transaction = ClipboardPasteTransaction(name: name)
  try await transaction.prepare("dictation")
  await transaction.restore()
  #expect(board.pasteboardItems?.count == 2)
  #expect(board.pasteboardItems?.first?.data(forType: .init("test.binary")) == Data([1, 2, 3]))
  try await transaction.prepare("dictation")
  board.clearContents()
  board.setString("newer user copy", forType: .string)
  await transaction.restore()
  #expect(board.string(forType: .string) == "newer user copy")
}

@Test @MainActor func suspendedDictationPreservesFinalSpeechWithoutInserting() async throws {
  let fixture = try DictationFixture()
  fixture.model.start(.toggle)
  try await waitForDictation { fixture.model.canFinish }
  fixture.model.suspend()
  await withCheckedContinuation { continuation in
    fixture.model.flushForTermination { continuation.resume() }
  }
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(fixture.history.results.first?.delivery == .needsPaste)
  #expect(fixture.history.results.first?.text.contains("Ștefan") == true)
  await fixture.finish()
}

@Test @MainActor func selectionCommandsRecoverEditedTextWhenInsertionFails() async throws {
  let fixture = try DictationFixture()
  await fixture.insertion.select("Please ship the report tomorrow.")
  let model = SelectionCommandCoordinator(
    history: fixture.history,
    services: .init(
      text: .init(
        insertion: fixture.insertion, cleanup: BoundedTextCleanup(),
        transform: { _, _ in "Ship the report tomorrow." }),
      currentApplication: fixture.currentApplication))
  await fixture.insertion.changeFocus()
  model.start(.shorten)
  try await waitForDictation { !model.isWorking }
  #expect(model.result?.text == "Ship the report tomorrow.")
  #expect(model.result?.delivery == .needsPaste)
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(fixture.history.results.first?.text == model.result?.text)
  await fixture.finish()
}

@Test @MainActor func cancelingSelectionCommandsRejectsLateModelOutput() async throws {
  let fixture = try DictationFixture()
  await fixture.insertion.select("Original selected text")
  let cleanup = CleanupFixture()
  let model = SelectionCommandCoordinator(
    history: fixture.history,
    services: .init(
      text: .init(
        insertion: fixture.insertion, cleanup: BoundedTextCleanup(),
        transform: { _, _ in await cleanup.run() }),
      currentApplication: fixture.currentApplication))
  model.start(.grammar)
  for _ in 0..<200 {
    if await cleanup.continuation != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  model.cancel()
  await cleanup.complete()
  try await Task.sleep(for: .milliseconds(20))
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(model.result == nil)
  #expect(!model.isWorking)
  await fixture.finish()
}

@Test @MainActor func dictationFeedbackWrapsItsContentAndNeverTakesKeyboardFocus() async throws {
  _ = NSApplication.shared
  let fixture = try DictationFixture()
  let panel = DictationPanelController()
  let priorKeyWindow = NSApp.keyWindow
  fixture.model.start(.toggle)
  try await waitForDictation { fixture.model.canFinish }
  panel.attach(
    to: .init(
      name: "Kiko", position: .init(x: 300, y: 300), characterSize: 64,
      windowLayer: 0, windowNumber: 0))
  panel.show(fixture.model, copy: { _ in }, history: {})
  let listening = try #require(panel.frame)
  #expect(listening.width <= WritingFeedbackLayout.width + 2 * WritingFeedbackLayout.shadowInset)
  #expect(listening.height < 220)
  #expect(NSApp.keyWindow === priorKeyWindow)
  await fixture.insertion.changeFocus()
  fixture.model.finish()
  try await waitForDictation { fixture.model.result != nil }
  panel.show(fixture.model, copy: { _ in }, history: {})
  let recovery = try #require(panel.frame)
  #expect(abs(recovery.height - listening.height) < 1)
  #expect(panel.layoutMeasurements == 1)
  #expect(recovery.height < 360)
  #expect(NSApp.keyWindow === priorKeyWindow)
  try renderSkillInterface(
    DictationFeedbackView(model: fixture.model, openSession: {}, copy: { _ in }),
    size: recovery.size, name: "sillies-dictation-recovery-preview")
  panel.close()
  await fixture.finish()
}

@Test @MainActor func dictationPermissionRecoveryUsesTheSameActionAsCaptureAndKeepsWords()
  async throws
{
  let fixture = try DictationFixture()
  await fixture.insertion.denyPermission()
  fixture.model.start(.toggle)
  try await waitForDictation { fixture.model.canFinish }
  #expect(fixture.model.insertionFailure?.recovery == .openAccessibilitySettings)
  #expect(
    SessionRecovery.settingsURL(for: .openAccessibilitySettings)?.absoluteString.hasSuffix(
      "Privacy_Accessibility") == true)
  try renderSkillInterface(
    DictationFeedbackView(model: fixture.model, openSession: {}, copy: { _ in }),
    size: .init(width: 448, height: 190), name: "sillies-dictation-permission-preview")
  try renderSkillInterface(
    DictationSessionView(model: fixture.model, companionName: "Kiko", copy: { _ in }, history: {}),
    size: .init(width: 560, height: 640), name: "sillies-dictation-session-permission-preview")
  fixture.model.finish()
  try await waitForDictation { fixture.model.result != nil }
  #expect(await fixture.insertion.inserted.isEmpty)
  #expect(fixture.model.result?.delivery == .needsPaste)
  #expect(fixture.history.results.count == 1)
  await fixture.finish()
}

@Test @MainActor func dictationDetailsKeepTheFullTranscriptAndDoNotStealFocus() async throws {
  let text = String(repeating: "Ștefan uses API_v2 at 16:30. ", count: 60)
  let fixture = try DictationFixture(text: text)
  fixture.model.start(.toggle)
  try await waitForDictation { fixture.model.preview == text }
  #expect(fixture.model.elapsed == 2)
  fixture.model.followsLiveTranscript = false
  let previousKeyWindow = NSApp.keyWindow
  let previousApplication = NSWorkspace.shared.frontmostApplication
  let details = DictationSessionWindowController()
  details.show(fixture.model, companionName: "Kiko", copy: { _ in }, history: {})
  #expect(NSApp.keyWindow === previousKeyWindow)
  #expect(NSWorkspace.shared.frontmostApplication == previousApplication)
  let window = try #require(details.window)
  #expect(
    WindowTrackingExclusions.excludesSurface(
      UInt32(window.windowNumber), ownerPID: ProcessInfo.processInfo.processIdentifier))
  #expect(!fixture.model.followsLiveTranscript)
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    try renderSkillInterface(
      DictationSessionView(
        model: fixture.model, companionName: "Kiko", copy: { _ in }, history: {}),
      size: .init(width: 560, height: 640), name: "sillies-dictation-session-\(appearance.rawValue)"
    )
  }
  NSApp.appearance = nil
  details.close()
  #expect(fixture.model.isActive)
  await fixture.finish()
}

@Test(arguments: [true, false]) @MainActor
func dictationHistoryFailureUsesTheSharedNoticeAndRetryWithoutLosingText(permissionGranted: Bool)
  async throws
{
  let fixture = try DictationFixture()
  await fixture.history.load()
  if !permissionGranted { await fixture.insertion.denyPermission() }
  let blocker = fixture.directory.appendingPathComponent("history.json")
  try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
  let panel = DictationPanelController()
  panel.attach(
    to: .init(
      name: "Kiko", position: .init(x: 300, y: 300), characterSize: 64, windowLayer: 0,
      windowNumber: 0))
  fixture.model.start(.toggle)
  try await waitForDictation { fixture.model.canFinish }
  panel.show(fixture.model, copy: { _ in }, history: {})
  let compact = try #require(panel.frame)
  fixture.model.finish()
  try await waitForDictation { fixture.model.result != nil }
  await fixture.history.flush()
  let failure = try #require(fixture.model.historyFailure)
  panel.show(fixture.model, copy: { _ in }, history: {})
  let warning = try #require(panel.frame)
  #expect(warning.width == compact.width)
  #expect(warning.height > compact.height)
  #expect(warning.height < 360)
  #expect(fixture.model.preview.contains("Ștefan"))
  try renderSkillInterface(
    WritingHistoryNotice(failure: failure, retry: {}), size: .init(width: 420, height: 170),
    name: "sillies-history-retry-notice")
  try renderSkillInterface(
    DictationSessionView(model: fixture.model, companionName: "Kiko", copy: { _ in }, history: {}),
    size: .init(width: 560, height: 640), name: "sillies-dictation-history-failure")
  try FileManager.default.removeItem(at: blocker)
  fixture.model.retryHistory()
  try await fixture.history.flush().get()
  #expect(fixture.model.historyFailure == nil)
  #expect(await fixture.insertion.inserted.count == (permissionGranted ? 1 : 0))
  panel.show(fixture.model, copy: { _ in }, history: {})
  #expect(panel.frame?.height == compact.height)
  #expect(fixture.model.result?.text.contains("Ștefan") == true)
  panel.close()
  await fixture.finish()
}
