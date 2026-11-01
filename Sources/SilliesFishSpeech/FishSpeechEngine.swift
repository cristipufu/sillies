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

  package init() {}

  package func prepare(directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    Memory.cacheLimit = Self.cacheBytes
    Memory.memoryLimit = min(
      Self.maximumMemoryBytes, Int(ProcessInfo.processInfo.physicalMemory / 2))
    if loaded?.directory != directory { try await load(directory) }
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
    let prompt = try loaded.prompt.tokens(for: request.text)
    loaded.decoder.reset()
    defer { loaded.decoder.reset() }
    try loaded.generator.stream(prompt: prompt) { frames in
      try receive(loaded.decoder.decodeNext(frames))
    }
  }

  private func load(_ directory: URL) async throws {
    loaded = nil
    let configuration = try FishConfiguration.decode(
      Data(contentsOf: directory.appendingPathComponent("config.json")))
    let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
    let prompt = FishPrompt(tokenizer: tokenizer, configuration: configuration)
    try prompt.validateTokenizer()
    try Task.checkCancellation()
    let weights = FishWeights(
      tensors: try loadArrays(url: directory.appendingPathComponent("model.safetensors")),
      quantization: configuration.quantization)
    let generator = try FishCodeGenerator(configuration: configuration, weights: weights)
    let allCodecWeights = try loadArrays(url: directory.appendingPathComponent("codec.safetensors"))
    let decoderWeights = allCodecWeights.filter { name, _ in
      name.hasPrefix("decoder.") || name.hasPrefix("quantizer.post_module.")
        || name.hasPrefix("quantizer.upsample.") || name.contains(".codebook.")
        || name.contains(".out_proj.")
    }
    loaded = Loaded(
      directory: directory, prompt: prompt, generator: generator,
      decoder: FishAudioDecoder(tensors: decoderWeights))
  }

  package static func configureMetalLibrary(_ url: URL) { GPU.metallib = url }

  package static func validateCompute() throws {
    guard (MLXArray([1, 2, 3]) * 2).sum().item(Int.self) == 12 else {
      throw FishError.invalidTensor("GPU self-test")
    }
  }
}
