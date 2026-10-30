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
  let registry = SpeechRuntimeRegistry(store: store, providers: [AppleSpeechProvider()])
  let updates = ModelUpdatesPresentation(
    checker: ModelUpdateChecker(
      store: store, location: directory.appendingPathComponent("updates.json")),
    registry: registry, defaults: defaults)
  let model = SpeechModelsPresentation(
    store: store, registry: registry, defaults: defaults, updates: updates)
  await model.load()
  #expect(model.manifests.count == 3)
  #expect(model.error == nil)
  try render(
    ScrollView { SpeechModelSettingsView(model: model, activeModelID: nil).padding(20) }.background(
      SilliesTheme.card),
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
  try render(
    sessionView, size: CGSize(width: 640, height: 760), name: "sillies-participate-preview")
  model.phase = .failed(
    .init(
      category: .audioProcessing,
      message:
        "Speech processing couldn’t keep pace with the audio. Finish to save the available transcript."
    ))
  model.reasoningNotice =
    "Apple’s on-device AI does not support this language. Your transcript is saved."
  model.speakerDetectionNotice =
    "Speaker detection stopped. Transcription continued without speaker labels."
  try render(
    sessionView, size: CGSize(width: 560, height: 640), name: "sillies-session-minimum-preview")
  for recovery in [
    SessionFailure.RecoveryAction.openMicrophoneSettings, .openScreenRecordingSettings,
  ] {
    model.phase = .failed(.permissionDenied(recovery))
    try render(
      sessionView, size: CGSize(width: 560, height: 640),
      name: "sillies-session-\(recovery.rawValue)-preview")
  }
  let recording = AudioSessionPresentation(kind: .record, sourceLabel: "MacBook Pro Microphone")
  recording.languages = model.languages
  recording.isLoadingLanguages = false
  recording.selectedLanguageID = fixtureEnglish.id
  recording.phase = .capturing
  try render(
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
  let vaultView = SessionVaultView(vault: vault, initialRecordID: record.id)
  try render(vaultView, size: CGSize(width: 980, height: 660), name: "sillies-vault-preview")
  let interrupted = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(transcript: model.transcript),
      notes: .init(summary: "Discuss system settings tomorrow. Keep these notes."),
      processing: .init(failure: .permissionDenied(.openScreenRecordingSettings))))
  vault.add(interrupted)
  try render(
    SessionVaultView(vault: vault, initialRecordID: interrupted.id),
    size: CGSize(width: 980, height: 660), name: "sillies-vault-permission-preview")
  await vault.flush()
}

@MainActor private func render(_ rootView: some View, size: CGSize, name: String) throws {
  let window = NSWindow(
    contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
    defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let host = NSHostingController(rootView: rootView)
  window.contentViewController = host
  let view = host.view
  view.frame = CGRect(origin: .zero, size: size)
  view.layoutSubtreeIfNeeded()
  let fitting = host.sizeThatFits(in: size)
  #expect(fitting.width <= size.width)
  #expect(fitting.height <= size.height)
  if let transcript = findTranscriptScrollView(in: view) {
    let viewport = view.convert(transcript.bounds, from: transcript)
    #expect(
      view.bounds.contains(viewport),
      "Transcript viewport must fit without clipping at minimum window size")
  }
  if ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" {
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png"))
  }
}
