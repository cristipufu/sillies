import Foundation
import SilliesCore
import SilliesInference
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesModelStore

@Test func voiceCatalogPinsEveryRuntimeResource() throws {
  let catalog = try TTSModelCatalog.bundled()
  #expect(
    Set(catalog.manifests.map { $0.model.providerID }) == [
      "kokoro", "pocket-tts", "qwen3-tts", "fish-speech", "woof", "vibevoice",
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
  let woof = try #require(catalog.manifests.first { $0.model.providerID == "woof" })
  #expect(woof.model.attribution?.text == "Voice by Underdog Woof")
  #expect(woof.model.attribution?.url.absoluteString == "https://underdog.ai")
  #expect(woof.model.voices.map(\.id) == ["juno", "mira"])
  #expect(woof.artifacts.contains { $0.path == "LICENSE" })
  #expect(woof.artifacts.contains { $0.path == "NOTICE" })
  let vibe = try #require(catalog.manifests.first { $0.model.providerID == "vibevoice" })
  #expect(vibe.model.voices.count == 6)
  #expect(vibe.model.streamsAudio && vibe.model.outputSampleRate == 24_000)
  for voice in vibe.model.voices {
    #expect(vibe.artifacts.contains { $0.path == "voices/\(voice.id).safetensors" })
  }
  #expect(vibe.artifacts.contains { $0.path == "tokenizer/tokenizer.json" })
  #expect(vibe.artifacts.contains { $0.path == "tokenizer/LICENSE" })
  #expect(!vibe.artifacts.contains { $0.path.hasSuffix(".pt") || $0.path.hasSuffix(".py") })
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

@Test func voiceCatalogRejectsUnsafeAttributionLinks() throws {
  let catalog = try TTSModelCatalog.bundled()
  for (credit, address) in [
    ("", "https://underdog.ai"),
    (String(repeating: "a", count: 161), "https://underdog.ai"),
    ("Voice credit", "file:///tmp/model"),
    ("Voice credit", "https://user:password@example.com"),
  ] {
    let original = try #require(catalog.manifests.first { $0.model.providerID == "woof" })
    var model = original.model
    model.attribution = .init(text: credit, url: try #require(URL(string: address)))
    let manifest = TTSModelManifest(
      model: model, components: original.components, artifacts: original.artifacts)
    #expect(throws: (any Error).self) { try manifest.validate() }
  }
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

@Test func voiceWarmupCanCancelWhileWaitingForAnotherNativeOperationToDrain() async throws {
  let activity = InferenceActivity()
  let text = UUID()
  let preempted = Mutex(false)
  let cancelled = Mutex(false)
  #expect(await activity.claimText(text, cancel: { preempted.withLock { $0 = true } }))
  let warmup = Task {
    do {
      try await activity.prepareSpeechRuntime { Issue.record("Cancelled warmup started its model") }
      Issue.record("Cancelled warmup succeeded")
    } catch is CancellationError {
      cancelled.withLock { $0 = true }
    } catch { Issue.record(error) }
  }
  let startDeadline = ContinuousClock.now.advanced(by: .seconds(1))
  while !preempted.withLock({ $0 }), ContinuousClock.now < startDeadline { await Task.yield() }
  #expect(preempted.withLock { $0 })
  warmup.cancel()
  let cancelDeadline = ContinuousClock.now.advanced(by: .seconds(1))
  while !cancelled.withLock({ $0 }), ContinuousClock.now < cancelDeadline { await Task.yield() }
  #expect(cancelled.withLock { $0 }, "Cancelling Talk must not depend on another native operation")
  await activity.releaseText(text)
  await warmup.value
  let voice = UUID()
  #expect(await activity.claimSynthesis(voice, cancel: {}))
  await activity.releaseSynthesis(voice)
}

@Test func voiceWarmupCancelledBeforeAdmissionDoesNotInterruptAnotherReply() async throws {
  let activity = InferenceActivity()
  let text = UUID()
  let preempted = Mutex(false)
  #expect(await activity.claimText(text, cancel: { preempted.withLock { $0 = true } }))
  let warmup = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    await #expect(throws: CancellationError.self) {
      try await activity.prepareSpeechRuntime { Issue.record("Cancelled startup prepared a model") }
    }
  }
  await warmup.value
  #expect(!preempted.withLock { $0 })
  await activity.releaseText(text)
}
