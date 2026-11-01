import Foundation
import MLX
import SilliesTTS
import Tokenizers

/// All tensors and caches belong to this actor in the disposable TTS helper process.
package actor FishSpeechEngine {
  private static let cacheBytes = 128 * 1_024 * 1_024
  private static let maximumMemoryBytes = 12 * 1_024 * 1_024 * 1_024
  private struct Loaded {
    let directory: URL
    let prompt: FishPrompt
    let generator: FishCodeGenerator
    let decoder: FishAudioDecoder
  }
  private var loaded: Loaded?
  private let profile: FishProfiler

  package init(profiling: FishProfileConfiguration? = nil) {
    profile = FishProfiler(configuration: profiling)
  }

  package func prepare(directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let requiresLoad = loaded?.directory != directory
    if requiresLoad { profile.begin(.loading) }
    defer { if requiresLoad { profile.finish() } }
    profile.measure(.memoryBudgetInitialization) {
      Memory.cacheLimit = Self.cacheBytes
      Memory.memoryLimit = min(
        Self.maximumMemoryBytes, Int(ProcessInfo.processInfo.physicalMemory / 2))
    }
    if requiresLoad { try await load(directory) }
  }

  package func synthesize(_ request: SpeechSynthesisRequest, directory: URL) async throws -> [Float]
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    var samples: [Float] = []
    try await stream(request, directory: directory) { samples.append(contentsOf: $0) }
    return samples
  }

  package func stream(
    _ request: SpeechSynthesisRequest, directory: URL,
    receive: ([Float]) throws -> Void
  ) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try request.validate()
    guard request.voiceID == "automatic" else { throw TTSError.unsupportedVoice }
    try await prepare(directory: directory)
    guard let loaded else { throw TTSError.interrupted }
    profile.begin(.synthesis)
    defer { profile.finish() }
    let prompt = try profile.measure(.promptTokens) { try loaded.prompt.tokens(for: request.text) }
    profile.promptTokens = prompt.count
    loaded.decoder.reset()
    defer { loaded.decoder.reset() }
    try loaded.generator.stream(prompt: prompt) { frames in
      profile.audioFrames += frames.count
      let samples = try profile.measure(.codecTotal) { try loaded.decoder.decodeNext(frames) }
      profile.generated(samples: samples.count)
      try profile.measure(.pcmDelivery) { try receive(samples) }
    }
  }

  private func load(_ directory: URL) async throws {
    loaded = nil
    let configuration = try profile.measure(.configuration) {
      try FishConfiguration.decode(
        Data(contentsOf: directory.appendingPathComponent("config.json")))
    }
    let tokenizerStarted = ProcessInfo.processInfo.systemUptime
    let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
    profile.record(.tokenizer, elapsed: ProcessInfo.processInfo.systemUptime - tokenizerStarted)
    let prompt = FishPrompt(tokenizer: tokenizer, configuration: configuration)
    try profile.measure(.tokenizerValidation) { try prompt.validateTokenizer() }
    try Task.checkCancellation()
    let weights = try profile.measure(.speechWeights) {
      FishWeights(
        tensors: try loadArrays(url: directory.appendingPathComponent("model.safetensors")),
        quantization: configuration.quantization)
    }
    let generator = try profile.measure(.generatorSetup) {
      try FishCodeGenerator(configuration: configuration, weights: weights, profile: profile)
    }
    let allCodecWeights = try profile.measure(.codecWeights) {
      try loadArrays(url: directory.appendingPathComponent("codec.safetensors"))
    }
    let decoderWeights = allCodecWeights.filter { name, _ in
      name.hasPrefix("decoder.") || name.hasPrefix("quantizer.post_module.")
        || name.hasPrefix("quantizer.upsample.") || name.contains(".codebook.")
        || name.contains(".out_proj.")
    }
    loaded = Loaded(
      directory: directory, prompt: prompt, generator: generator,
      decoder: FishAudioDecoder(tensors: decoderWeights, profile: profile))
  }

  package static func configureMetalLibrary(_ url: URL) { GPU.metallib = url }

  package static func validateCompute() throws {
    guard (MLXArray([1, 2, 3]) * 2).sum().item(Int.self) == 12 else {
      throw FishError.invalidTensor("GPU self-test")
    }
  }
}
