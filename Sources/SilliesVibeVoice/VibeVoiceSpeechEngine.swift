import Foundation
import MLX
import SilliesTTS
import Tokenizers

/// Model, tokenizer, voice caches and decoder histories stay inside the killable helper.
package actor VibeVoiceSpeechEngine {
  private struct Loaded {
    let directory: URL
    let configuration: VibeVoiceConfiguration
    let tokenizer: any Tokenizer
    let generator: VibeVoiceGenerator
    let decoder: VibeVoiceAudioDecoder
  }
  private struct PreparedVoice {
    let id: String
    let prompt: VibeVoicePrompt
  }
  package static let sampleRate = 24_000
  private static let maximumWeightBytes = 1_280 * 1_024 * 1_024
  private static let maximumConfigurationBytes = 64 * 1_024
  private static let cacheBytes = 128 * 1_024 * 1_024
  private static let memoryBytes = 4 * 1_024 * 1_024 * 1_024
  private static let maximumTextTokens = 1_024
  private var loaded: Loaded?
  private var voice: PreparedVoice?

  package init() {}

  package func prepare(directory: URL, voiceID: String) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    if loaded?.directory != directory {
      loaded = nil
      voice = nil
      Memory.cacheLimit = Self.cacheBytes
      Memory.memoryLimit = min(Self.memoryBytes, Int(ProcessInfo.processInfo.physicalMemory / 2))
      loaded = try await load(directory)
    }
    guard let loaded else { throw TTSError.interrupted }
    guard (1...64).contains(voiceID.utf8.count),
      voiceID.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      })
    else { throw TTSError.unsupportedVoice }
    if voice?.id != voiceID {
      voice = nil
      let url = directory.appendingPathComponent("voices").appendingPathComponent(
        voiceID + ".safetensors")
      voice = try PreparedVoice(
        id: voiceID, prompt: VibeVoicePrompt(url: url, configuration: loaded.configuration))
    }
  }

  package func stream(
    _ request: SpeechSynthesisRequest, directory: URL,
    receive: ([Float]) throws -> Void
  ) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try request.validate()
    let language = request.language.replacingOccurrences(of: "_", with: "-").lowercased()
    guard language.split(separator: "-").first == "en" else { throw TTSError.unsupportedLanguage }
    try await prepare(directory: directory, voiceID: request.voiceID)
    guard let loaded, let voice else { throw TTSError.interrupted }
    let encoded = loaded.tokenizer.encode(
      text: request.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n",
      addSpecialTokens: false)
    guard !encoded.isEmpty, encoded.count <= Self.maximumTextTokens else {
      throw TTSError.invalidRequest
    }
    let tokens = try encoded.map { value -> Int32 in
      guard value >= 0, value < loaded.configuration.transformer.vocabularySize,
        let token = Int32(exactly: value)
      else {
        throw TTSError.invalidRequest
      }
      return token
    }
    do {
      try loaded.generator.stream(
        tokens: tokens, prompt: voice.prompt, decoder: loaded.decoder, receive: receive)
    } catch is VibeVoiceError { throw TTSError.invalidAudio }
  }

  private func load(_ directory: URL) async throws -> Loaded {
    let configURL = directory.appendingPathComponent("config.json")
    try validateSize(configURL, maximum: Self.maximumConfigurationBytes)
    let configuration = try JSONDecoder().decode(
      VibeVoiceConfiguration.self, from: Data(contentsOf: configURL))
    try configuration.validate()
    let weightURL = directory.appendingPathComponent("model.safetensors")
    try validateSize(weightURL, maximum: Self.maximumWeightBytes)
    let weights = VibeVoiceWeights(
      tensors: try loadArrays(url: weightURL), quantization: configuration.quantization)
    let tokenizer = try await AutoTokenizer.from(
      modelFolder: directory.appendingPathComponent("tokenizer"))
    try Task.checkCancellation()
    return try Loaded(
      directory: directory, configuration: configuration, tokenizer: tokenizer,
      generator: VibeVoiceGenerator(configuration: configuration, weights: weights),
      decoder: VibeVoiceAudioDecoder(configuration: configuration.codec, weights: weights))
  }

  private func validateSize(_ url: URL, maximum: Int) throws {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size > 0, size <= maximum else { throw VibeVoiceError.unsupportedConfiguration }
  }
}
