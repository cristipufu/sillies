import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS
import Synchronization
import Testing

@Test func voiceCatalogPinsEveryRuntimeResource() throws {
  let catalog = try TTSModelCatalog.bundled()
  #expect(
    Set(catalog.manifests.map { $0.model.providerID }) == [
      "kokoro", "pocket-tts", "qwen3-tts", "fish-speech",
    ])
  for manifest in catalog.manifests {
    try manifest.validate()
    #expect(manifest.artifacts.allSatisfy { !$0.url.absoluteString.contains("/main/") })
    #expect(manifest.model.supports(language: "en-US"))
    #expect(manifest.model.supports(language: "ro") == (manifest.model.providerID == "fish-speech"))
  }
  let pocket = try #require(catalog.manifests.first { $0.model.providerID == "pocket-tts" })
  #expect(pocket.artifacts.allSatisfy { $0.path.contains("/v2.1/english/") })
  #expect(pocket.artifacts.contains { $0.path.hasSuffix("bos_before_voice.bin") })
  let kokoro = try #require(catalog.manifests.first { $0.model.providerID == "kokoro" })
  #expect(kokoro.artifacts.contains { $0.path == "kokoro/us_lexicon_cache.json" })
}

@Test func speechAudioRejectsInvalidNativeInputs() throws {
  for samples in [
    [Float](), [Float.nan], [.infinity], [9], Array(repeating: Float(0), count: 4_097),
  ] {
    #expect(throws: TTSError.self) { try SynthesizedAudio(samples: samples, sampleRate: 24_000) }
  }
  for rate in [0, -1, Int.max, 1_000] {
    #expect(throws: TTSError.self) { try SynthesizedAudio(samples: [0.1], sampleRate: rate) }
  }
  let decoded = try JSONDecoder().decode(
    SynthesizedAudio.self, from: Data("{\"samples\":[],\"sampleRate\":24000}".utf8))
  #expect(throws: TTSError.self) { try decoded.validate() }
}

@Test func voiceWorkerExitIsRecoverable() async throws {
  let runtime = try await WorkerTTSProvider(
    id: "test", executable: URL(fileURLWithPath: "/usr/bin/false")
  ).prepare(
    .init(
      directory: URL(fileURLWithPath: "/tmp/absent-voice-model"), providerID: "test",
      variant: "test"))
  for _ in 0..<2 {
    await #expect(throws: (any Error).self) {
      try await runtime.synthesize(.init(text: "Hello", voiceID: "voice", language: "en")) { _ in }
    }
  }
  await runtime.stop()
}

@Test func voicePreemptsTextAndMicrophonePreemptsVoice() async throws {
  let activity = InferenceActivity()
  let text = UUID()
  let voice = UUID()
  let textCancelled = Mutex(false)
  let voiceCancelled = Mutex(false)
  #expect(await activity.claimText(text, cancel: { textCancelled.withLock { $0 = true } }))
  let synthesis = Task {
    await activity.claimSynthesis(voice, cancel: { voiceCancelled.withLock { $0 = true } })
  }
  for _ in 0..<100 {
    if textCancelled.withLock({ $0 }) { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(textCancelled.withLock { $0 })
  await activity.releaseText(text)
  #expect(await synthesis.value)
  #expect(await activity.claimText(UUID(), cancel: {}) == false)
  let speech = Task { await activity.beginSpeech() }
  for _ in 0..<100 {
    if voiceCancelled.withLock({ $0 }) { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(voiceCancelled.withLock { $0 })
  await activity.releaseSynthesis(voice)
  await speech.value
  #expect(await activity.claimText(UUID(), cancel: {}) == false)
  await activity.endSpeech()
  let next = UUID()
  #expect(await activity.claimText(next, cancel: {}))
  await activity.releaseText(next)
}

@Test func voiceWarmupReleasesInferenceAdmissionOnSuccessAndFailure() async throws {
  let activity = InferenceActivity()
  try await activity.prepareSpeechRuntime {
    #expect(await activity.claimText(UUID(), cancel: {}) == false)
  }
  let text = UUID()
  #expect(await activity.claimText(text, cancel: {}))
  await activity.releaseText(text)
  await #expect(throws: CancellationError.self) {
    try await activity.prepareSpeechRuntime { throw CancellationError() }
  }
  let voice = UUID()
  #expect(await activity.claimSynthesis(voice, cancel: {}))
  await activity.releaseSynthesis(voice)
}
