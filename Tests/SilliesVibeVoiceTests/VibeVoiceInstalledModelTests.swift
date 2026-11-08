import Foundation
import MLX
import SilliesTTS
import Testing

@testable import SilliesVibeVoice

/// Opt-in numerical and synthesis checks. Never downloads weights or opens an audio device.
@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["SILLIES_VIBEVOICE_MODEL"] != nil))
struct VibeVoiceInstalledModelTests {
  init() throws { _ = try VibeVoiceRuntimeTests() }

  @Test func retainedVoiceStartsEveryUtteranceWithIndependentState() async throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_VIBEVOICE_MODEL"]))
    let engine = VibeVoiceSpeechEngine()
    var baseline: [Float] = []
    for seed in UInt64(0)..<6 {
      let samples = try await seededSpeech(engine, directory: directory, seed: seed)
      if seed == 0 { baseline = samples }
      print("VibeVoice Carter seed \(seed): \(samples.count) samples")
    }
    let repeated = try await seededSpeech(engine, directory: directory, seed: 0)
    let fresh = try await seededSpeech(VibeVoiceSpeechEngine(), directory: directory, seed: 0)
    for samples in [repeated, fresh] {
      try #require(samples.count == baseline.count)
      #expect(zip(samples, baseline).allSatisfy { abs($0 - $1) < 1e-5 })
    }
  }

  @Test func completeUtteranceMatchesPublisherReference() async throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_VIBEVOICE_MODEL"]))
    let samples = try await seededSpeech(VibeVoiceSpeechEngine(), directory: directory, seed: 1)
    try compare(MLXArray(samples), named: "utterance-carter-seed-1")
  }

  private func seededSpeech(_ engine: VibeVoiceSpeechEngine, directory: URL, seed: UInt64)
    async throws -> [Float]
  {
    try await withRandomState(MLXRandom.RandomState(seed: seed)) {
      var samples: [Float] = []
      try await engine.stream(
        .init(
          text: "Hello! I am your little window companion.", voiceID: "en-Carter_man",
          language: "en"),
        directory: directory
      ) { samples += $0 }
      return samples
    }
  }

  @Test func stagesMatchMicrosoftReferenceAndSynthesisRecoversAfterCancellation() async throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_VIBEVOICE_MODEL"]))
    try validateStages(directory: directory)
    let engine = VibeVoiceSpeechEngine()
    var samples: [Float] = []
    var firstChunk: TimeInterval?
    let start = ProcessInfo.processInfo.systemUptime
    let request = SpeechSynthesisRequest(
      text: "Hello! I am your little window companion.", voiceID: "en-Emma_woman", language: "en")
    try await engine.stream(request, directory: directory) { chunk in
      if firstChunk == nil { firstChunk = ProcessInfo.processInfo.systemUptime - start }
      samples += chunk
    }
    #expect(samples.count > VibeVoiceSpeechEngine.sampleRate)
    #expect(samples.contains { abs($0) > 0.01 })
    #expect(samples.allSatisfy { $0.isFinite })
    print(
      "VibeVoice Emma: first chunk \(firstChunk ?? -1)s, total \(ProcessInfo.processInfo.systemUptime - start)s, samples \(samples.count)"
    )
    await #expect(throws: CancellationError.self) {
      try await engine.stream(request, directory: directory) { _ in throw CancellationError() }
    }
    var recovered = 0
    try await engine.stream(request, directory: directory) { recovered += $0.count }
    #expect(recovered > VibeVoiceSpeechEngine.sampleRate)
  }

  private func validateStages(directory: URL) throws {
    let configuration = try JSONDecoder().decode(
      VibeVoiceConfiguration.self,
      from: Data(contentsOf: directory.appendingPathComponent("config.json")))
    try configuration.validate()
    let weights = VibeVoiceWeights(
      tensors: try loadArrays(url: directory.appendingPathComponent("model.safetensors")),
      quantization: configuration.quantization)
    let prompt = try VibeVoicePrompt(
      url: directory.appendingPathComponent("voices/en-Emma_woman.safetensors"),
      configuration: configuration)
    struct Report: Decodable { let tokens: [Int32] }
    let report = try JSONDecoder().decode(
      Report.self, from: Data(contentsOf: referenceURL("report", fileExtension: "json"))
    )
    let embedding = try weights.embedding(
      "language_model.embed_tokens", rows: configuration.transformer.vocabularySize,
      dimensions: configuration.transformer.dimensions)
    let text = try VibeVoiceTransformer(
      configuration: configuration.transformer, weights: weights,
      stack: .init(path: "language_model", layerCount: 4))
    var textCache = prompt.text
    let hidden = try text(embedding(Array(report.tokens.prefix(5))), caches: &textCache)
    try compare(hidden, named: "text-hidden")
    var exhausted = prompt.text
    let fullCache = MLXArray.zeros([1, 2, configuration.transformer.maximumContext, 64])
    exhausted[0] = .init(keys: fullCache, values: fullCache)
    #expect(throws: TTSError.self) {
      _ = try text(embedding([report.tokens[0]]), caches: &exhausted)
    }
    let speech = try VibeVoiceTransformer(
      configuration: configuration.transformer, weights: weights,
      stack: .init(
        path: "tts_language_model", layerCount: 20,
        finalNorm: weights.tensor(
          "tts_language_model.norm.weight", shape: [configuration.transformer.dimensions])))
    let types = try weights.embedding(
      "tts_input_types", rows: 2, dimensions: configuration.transformer.dimensions)
    var speechCache = prompt.speech
    let spoken = try speech(hidden + types([1]), caches: &speechCache)
    try compare(spoken, named: "speech-hidden")
    let diffusion = try VibeVoiceDiffusion(configuration: configuration.diffusion, weights: weights)
    let noise = try MLXArray(read("diffusion-noise")).reshaped(1, 64)
    let latent = try diffusion.sample(
      positive: spoken[(-1)...], negative: prompt.negativeCondition, noise: noise)
    try compare(latent, named: "diffusion-latent")
    let decoder = try VibeVoiceAudioDecoder(configuration: configuration.codec, weights: weights)
    let codecInput = try MLXArray(read("codec-input")).reshaped(3, 64)
    for index in 0..<3 {
      let samples = try decoder.decode(codecInput[index..<(index + 1)])
      try compare(MLXArray(samples), named: "codec-output-\(index)")
    }
  }

  private func referenceURL(_ name: String, fileExtension suffix: String) throws -> URL {
    try #require(
      Bundle.module.url(
        forResource: name, withExtension: suffix, subdirectory: "Fixtures/Reference"))
  }

  private func read(_ name: String) throws -> [Float] {
    let data = try Data(contentsOf: referenceURL(name, fileExtension: "f32"))
    try #require(!data.isEmpty && data.count.isMultiple(of: MemoryLayout<Float>.size))
    return data.withUnsafeBytes { bytes in
      stride(from: 0, to: bytes.count, by: MemoryLayout<Float>.size).map {
        bytes.loadUnaligned(fromByteOffset: $0, as: Float.self)
      }
    }
  }

  private func compare(_ actual: MLXArray, named name: String) throws {
    let values = actual.asArray(Float.self)
    let expected = try read(name)
    try #require(values.count == expected.count)
    let error = zip(values, expected).reduce(0.0) { $0 + pow(Double($1.0 - $1.1), 2) }
    let energy = expected.reduce(0.0) { $0 + pow(Double($1), 2) }
    let relativeError = sqrt(error / max(energy, 1e-12))
    print("VibeVoice reference \(name): relative RMS error \(relativeError)")
    #expect(relativeError < 0.001)
  }
}
