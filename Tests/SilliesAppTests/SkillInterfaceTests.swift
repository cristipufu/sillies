import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

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
    "Speech processing couldn’t keep pace with the audio. Finish to save the available transcript.")
  model.reasoningNotice =
    "Apple’s on-device AI does not support this language. Your transcript is saved."
  try render(
    sessionView, size: CGSize(width: 560, height: 640), name: "sillies-session-minimum-preview")
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
    kind: .participate, characterID: "mochi", characterName: "Mochi", appName: "Design review",
    durationSeconds: 125, transcript: model.transcript,
    summary: "The proposal is due next week. A reviewer is still needed.",
    actionItems: ["Coordinate the customer call."], suggestions: [suggestion])
  vault.add(record)
  let vaultView = SessionVaultView(vault: vault, initialRecordID: record.id)
  try render(vaultView, size: CGSize(width: 980, height: 660), name: "sillies-vault-preview")
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
  if ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" {
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png"))
  }
}
