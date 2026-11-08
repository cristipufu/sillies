import CryptoKit
import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS
import Testing

@Test(arguments: ["kokoro", "pocket-tts", "qwen3-tts", "fish-speech", "woof", "vibevoice"])
func voicePreparationReusesTheInstalledRuntimeAcrossTurns(providerID: String) async throws {
  let fixture = try VoiceRegistryFixture(providerID: providerID)
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe()
  let registry = try fixture.registry(probe)
  for _ in 0..<2 {
    #expect(
      try await registry.prepareVoiceIfPossible(
        .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: UUID()))
    try await registry.synthesize(
      .init(text: "Hello", voiceID: "voice", language: "en"), using: fixture.manifest,
      receive: { _ in })
  }
  #expect(await probe.loads == 1)
  #expect(await probe.preparations == 2)
  #expect(await probe.utterances == 2)
  await registry.stop()
  #expect(await probe.stops == 1)
}

@Test func voiceConversationRetentionEndsAndMemoryPressureCanEvictIt() async throws {
  let fixture = try VoiceRegistryFixture()
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe()
  let registry = try fixture.registry(probe, idle: .milliseconds(20))
  let lifetime = SpeechModelLifetime()
  await registry.retain(for: lifetime)
  #expect(
    try await registry.prepareVoiceIfPossible(
      .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: UUID()))
  try await Task.sleep(for: .milliseconds(80))
  #expect(await probe.stops == 0)
  await registry.setRetention(.memoryPressure)
  #expect(await probe.stops == 1)
  #expect(
    try await !registry.prepareVoiceIfPossible(
      .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: UUID()))
  await registry.setRetention(.available)
  #expect(
    try await registry.prepareVoiceIfPossible(
      .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: UUID()))
  await lifetime.end()
  for _ in 0..<100 {
    if await probe.stops == 2 { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await probe.stops == 2)
  await registry.stop()
}

@Test func voicePreparationDefersWithoutLoadingWhenTextNeedsTheMemoryBudget() async throws {
  let fixture = try VoiceRegistryFixture()
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe()
  let activity = InferenceActivity(overlapBudget: 1)
  let registry = try fixture.registry(probe, activity: activity)
  let turn = UUID()
  let text = UUID()
  #expect(
    await activity.claimText(
      text, reservation: .init(conversationID: turn, modelBytes: 1), cancel: {}))
  #expect(
    try await !registry.prepareVoiceIfPossible(
      .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: turn))
  #expect(await probe.loads == 0)
  await activity.releaseText(text)
  await registry.stop()
}

@Test func voicePreparationPreemptionDefersAndLeavesTheRegistryUsable() async throws {
  let fixture = try VoiceRegistryFixture()
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe(preparationDelay: .seconds(30))
  let activity = InferenceActivity()
  let registry = try fixture.registry(probe, activity: activity)
  let preparation = Task {
    try await registry.prepareVoiceIfPossible(
      .init(id: "voice", language: "en"), using: fixture.manifest, conversationID: UUID())
  }
  for _ in 0..<100 {
    if await probe.preparations > 0 { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await probe.preparations == 1)
  let text = UUID()
  #expect(await !activity.claimText(text, cancel: {}))
  #expect(try await !preparation.value)
  #expect(await probe.stops == 1)
  #expect(await activity.claimText(text, cancel: {}))
  await activity.releaseText(text)
  try await registry.synthesize(
    .init(text: "Hello again", voiceID: "voice", language: "en"), using: fixture.manifest,
    receive: { _ in })
  #expect(await probe.utterances == 1)
  await registry.stop()
}

@Test func firstVoicePhraseWaitsForRecognitionInsteadOfReportingAnotherSpeaker() async throws {
  let fixture = try VoiceRegistryFixture()
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe()
  let activity = InferenceActivity()
  let registry = try fixture.registry(probe, activity: activity)
  await activity.beginSpeech()
  let voice = Task {
    try await registry.synthesize(
      .init(text: "The reply is still ready.", voiceID: "voice", language: "en"),
      using: fixture.manifest, receive: { _ in })
  }
  try await Task.sleep(for: .milliseconds(20))
  #expect(await probe.loads == 0)
  #expect(await probe.utterances == 0)
  await activity.endSpeech()
  try await voice.value
  #expect(await probe.loads == 1)
  #expect(await probe.utterances == 1)
  await registry.stop()
}

@Test func cancellingVoiceWaitingForRecognitionLeavesTheNextTurnAvailable() async throws {
  let fixture = try VoiceRegistryFixture()
  defer { fixture.remove() }
  let probe = PreparedVoiceProbe()
  let activity = InferenceActivity()
  let registry = try fixture.registry(probe, activity: activity)
  await activity.beginSpeech()
  let voice = Task {
    try await registry.synthesize(
      .init(text: "This reply was superseded.", voiceID: "voice", language: "en"),
      using: fixture.manifest, receive: { _ in })
  }
  try await Task.sleep(for: .milliseconds(20))
  voice.cancel()
  await #expect(throws: CancellationError.self) { try await voice.value }
  #expect(await probe.loads == 0)
  await activity.endSpeech()
  try await registry.synthesize(
    .init(text: "The next reply.", voiceID: "voice", language: "en"),
    using: fixture.manifest, receive: { _ in })
  #expect(await probe.utterances == 1)
  await registry.stop()
}

private actor PreparedVoiceProbe: PreparedTTSModel {
  private let preparationDelay: Duration
  var loads = 0
  var preparations = 0
  var utterances = 0
  var stops = 0
  init(preparationDelay: Duration = .zero) { self.preparationDelay = preparationDelay }
  func loaded() { loads += 1 }
  func prepareVoice(_ voice: SpeechVoice) async throws {
    preparations += 1
    try await Task.sleep(for: preparationDelay)
  }
  func synthesize(_ request: SpeechSynthesisRequest, receive: SynthesizedAudioSink) async throws {
    utterances += 1
    try await receive(.init(samples: [0.1], sampleRate: 24_000))
  }
  func stop() { stops += 1 }
}

private struct PreparedVoiceProvider: TTSProvider {
  let id: String
  let probe: PreparedVoiceProbe
  func prepare(_ configuration: TTSPreparation) async throws -> any PreparedTTSModel {
    await probe.loaded()
    return probe
  }
}

private struct VoiceRegistryFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-voice-registry-\(UUID())")
  let manifest: TTSModelManifest

  init(providerID: String = "fixture") throws {
    let revision = String(repeating: "a", count: 40)
    let data = Data("voice".utf8)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let json: [String: Any] = [
      "model": [
        "id": "fixture", "providerID": providerID, "runtimeVariant": "fixture", "name": "Fixture",
        "detail": "Test", "revision": revision, "license": "MIT",
        "sourceURL": "https://huggingface.co/fixture/voice",
        "minimumMemoryGB": 1, "languages": ["en"], "streamsAudio": true,
        "voices": [["id": "voice", "name": "Fixture", "languages": ["en"]]],
      ],
      "components": [
        [
          "directory": "", "repository": "fixture/voice", "revision": revision,
          "sourceDirectory": "",
        ]
      ],
      "artifacts": [
        [
          "path": "weights.bin",
          "url": "https://huggingface.co/fixture/voice/resolve/\(revision)/weights.bin",
          "byteCount": data.count, "sha256": digest,
        ]
      ],
    ]
    manifest = try JSONDecoder().decode(
      TTSModelManifest.self, from: JSONSerialization.data(withJSONObject: json))
    let installed = root.appendingPathComponent("fixture/\(revision)")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try data.write(to: installed.appendingPathComponent("weights.bin"))
    try JSONSerialization.data(withJSONObject: ["revision": revision]).write(
      to: installed.appendingPathComponent("installed.json"))
  }
  func registry(
    _ probe: PreparedVoiceProbe, activity: InferenceActivity = InferenceActivity(),
    idle: Duration = .seconds(60)
  ) throws -> TTSModelRegistry {
    try TTSModelRegistry(
      store: ModelStore(root: root),
      providers: [PreparedVoiceProvider(id: manifest.model.providerID, probe: probe)],
      activity: activity, idleDuration: idle)
  }
  func remove() {
    do { try FileManager.default.removeItem(at: root) } catch {
      Issue.record("Fixture cleanup: \(error)")
    }
  }
}
