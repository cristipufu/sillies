import AppKit
import SilliesAudioTestSupport
import SilliesCore
import SilliesModelStore
import SilliesSpeechApple
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func downloadableModelSettingsFitTheSettingsWidth() async throws {
  let suite = "sillies-model-ui-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let store = ModelStore(root: directory)
  let registry = try SpeechRuntimeRegistry(store: store, providers: [AppleSpeechProvider()])
  let updates = ModelUpdatesPresentation(
    checker: ModelUpdateChecker(
      store: store, location: directory.appendingPathComponent("updates.json")),
    registry: registry, defaults: defaults)
  let model = SpeechModelsPresentation(
    store: store, registry: registry, defaults: defaults, updates: updates)
  await model.load()
  #expect(model.manifests.count == 4)
  #expect(model.error == nil)
  try renderSkillInterface(
    ScrollView { SpeechModelSettingsView(model: model, activeModelID: nil).padding(20) }.background(
      SilliesTheme().card),
    size: CGSize(width: 520, height: 600), name: "sillies-speech-model-settings")
}

@Test @MainActor func sessionAndVaultInterfacesRenderWithMeetingAndRecordingContent() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let model = AudioSessionPresentation(
    kind: .participate, sourceLabel: "Meeting app + MacBook Pro Microphone")
  model.phase = .capturing
  model.status = "Transcribing"
  model.elapsed = 125
  model.languages = [fixtureEnglish, fixtureFrench]
  model.isLoadingLanguages = false
  model.selectedLanguageID = fixtureEnglish.id
  model.diarizationModel = try SpeechModelCatalog.bundled().manifest(for: "nemotron-speakers").model
  model.transcript =
    "[01:24] Meeting: We will send the proposal next week. Nobody has been assigned to review it.\n[01:31] You · microphone: I can coordinate the customer call."
  let suggestion = MeetingSuggestion(
    question: "Who will review the proposal?", evidence: "Nobody has been assigned to review it.",
    elapsed: 100)
  model.suggestions = [suggestion]
  let sessionView = AudioSessionView(model: model)
  try renderSkillInterface(
    sessionView, size: CGSize(width: 640, height: 760), name: "sillies-participate-preview")
  model.phase = .failed(
    .init(
      category: .audioProcessing,
      message:
        "Speech processing couldn’t keep pace with the audio. Finish to save the available transcript."
    ))
  model.reasoningAvailability = .unavailable(
    "Apple’s on-device AI does not support this language. Your transcript is saved.")
  model.speakerDetectionNotice =
    "Speaker detection stopped. Transcription continued without speaker labels."
  try renderSkillInterface(
    sessionView, size: CGSize(width: 560, height: 640), name: "sillies-session-minimum-preview")
  for recovery in [
    SessionFailure.RecoveryAction.openMicrophoneSettings, .openScreenRecordingSettings,
  ] {
    model.phase = .failed(.permissionDenied(recovery))
    try renderSkillInterface(
      sessionView, size: CGSize(width: 560, height: 640),
      name: "sillies-session-\(recovery.rawValue)-preview")
  }
  let recording = AudioSessionPresentation(kind: .record, sourceLabel: "MacBook Pro Microphone")
  recording.languages = model.languages
  recording.isLoadingLanguages = false
  recording.selectedLanguageID = fixtureEnglish.id
  recording.phase = .capturing
  try renderSkillInterface(
    AudioSessionView(model: recording), size: CGSize(width: 640, height: 760),
    name: "sillies-record-language-preview")
  let vault = SessionVaultStore(directory: directory)
  let record = SessionRecord(
    kind: .participate,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Design review")),
    content: .init(
      text: .init(transcript: model.transcript),
      notes: .init(
        summary: "The proposal is due next week. A reviewer is still needed.",
        actionItems: ["Coordinate the customer call."], suggestions: [suggestion])),
    metadata: .init(durationSeconds: 125))
  vault.add(record)
  let vaultModel = SessionVaultModel(vault: vault, presentation: .init(initialRecordID: record.id))
  await vaultModel.refreshSearch()
  await vaultModel.loadSelection()
  let vaultView = SessionVaultView(
    vault: vault, conversations: nil, model: vaultModel)
  try renderSkillInterface(
    vaultView, size: CGSize(width: 980, height: 660), name: "sillies-vault-preview")
  vaultModel.openTranscript(record)
  try renderSkillInterface(
    vaultView, size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-full-transcript")
  vaultModel.closeTranscript()
  let interrupted = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(transcript: model.transcript),
      notes: .init(summary: "Discuss system settings tomorrow. Keep these notes."),
      processing: .init(failure: .permissionDenied(.openScreenRecordingSettings))))
  vault.add(interrupted)
  let interruptedModel = SessionVaultModel(
    vault: vault, presentation: .init(initialRecordID: interrupted.id))
  await interruptedModel.refreshSearch()
  await interruptedModel.loadSelection()
  try renderSkillInterface(
    SessionVaultView(
      vault: vault, conversations: nil,
      model: interruptedModel),
    size: CGSize(width: 980, height: 660), name: "sillies-vault-permission-preview")
  await vault.flush()
}

@MainActor func renderSkillInterface(_ rootView: some View, size: CGSize, name: String) throws {
  let fixture = SkillInterfaceRenderFixture(rootView: rootView, size: size)
  defer { fixture.close() }
  try fixture.capture(name: name)
}

/// Allows actual asynchronous view tasks to finish before reviewing their populated appearance.
@MainActor func renderSettledSkillInterface(_ rootView: some View, size: CGSize, name: String)
  async throws
{
  let fixture = SkillInterfaceRenderFixture(rootView: rootView, size: size)
  defer { fixture.close() }
  let initialPresentationDelay = Duration.milliseconds(250)
  try await Task.sleep(for: initialPresentationDelay)
  try fixture.capture(name: name)
}

@MainActor private final class SkillInterfaceRenderFixture<Content: View> {
  private let window: NSWindow
  private let host: NSHostingController<Content>
  private let size: CGSize

  init(rootView: Content, size: CGSize) {
    self.size = size
    window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    host = NSHostingController(rootView: rootView)
    host.sizingOptions = []
    window.contentViewController = host
    host.view.frame = CGRect(origin: .zero, size: size)
    window.setContentSize(size)
  }

  func close() { window.close() }

  func capture(name: String) throws {
    let view = host.view
    view.layoutSubtreeIfNeeded()
    #expect(view.bounds.size == size)
    let fitting = host.sizeThatFits(in: size)
    #expect(fitting.width <= size.width)
    #expect(fitting.height <= size.height)
    if let transcript = findTranscriptScrollView(in: view) {
      let viewport = view.convert(transcript.bounds, from: transcript)
      #expect(
        view.bounds.contains(viewport),
        "Transcript viewport must fit without clipping at minimum window size")
    }
    if let editor = findVaultEditor(in: view) {
      let viewport = view.convert(editor.bounds, from: editor)
      let minimumReadingHeight: CGFloat = 120
      #expect(view.bounds.contains(viewport), "The Vault editor must remain inside the workspace.")
      #expect(
        viewport.height >= minimumReadingHeight, "Controls and errors must leave room to read.")
    }
    if ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" {
      let snapshotLayoutInterval: TimeInterval = 0.05
      RunLoop.main.run(until: Date().addingTimeInterval(snapshotLayoutInterval))
      view.layoutSubtreeIfNeeded()
      view.displayIfNeeded()
      CATransaction.flush()
      let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: rep)
      let data = try #require(rep.representation(using: .png, properties: [:]))
      try data.write(
        to: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png"))
    }
  }

  private func findVaultEditor(in view: NSView) -> NSView? {
    if view.identifier == VaultNativeTextEditor.scrollIdentifier { return view }
    for child in view.subviews {
      if let editor = findVaultEditor(in: child) { return editor }
    }
    return nil
  }
}
