import Foundation
import MLX
import SilliesTTS

/// All mutable tensors are confined to this actor inside the killable voice inference helper.
package actor WoofSpeechEngine {
  private struct Loaded {
    let directory: URL
    let generator: WoofLatentGenerator
    let decoder: WoofAudioDecoder
    let mean: MLXArray
    let deviation: MLXArray
    let voices: [String: MLXArray]
  }
  private static let cacheBytes = 64 * 1_024 * 1_024
  private static let maximumMemoryBytes = 2 * 1_024 * 1_024 * 1_024
  package static let sampleRate = WoofConfiguration.sampleRate
  private var loaded: Loaded?

  package init() {}

  package func prepare(directory: URL, voiceID: String) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    if loaded?.directory != directory {
      loaded = nil
      Memory.cacheLimit = Self.cacheBytes
      Memory.memoryLimit = min(
        Self.maximumMemoryBytes, Int(ProcessInfo.processInfo.physicalMemory / 2))
      loaded = try load(directory)
    }
    guard loaded?.voices[voiceID] != nil else { throw TTSError.unsupportedVoice }
  }

  package func stream(
    _ request: SpeechSynthesisRequest, directory: URL, seed: UInt32? = nil,
    receive: ([Float]) throws -> Void
  ) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try request.validate()
    let language = request.language.replacingOccurrences(of: "_", with: "-").lowercased()
    guard language.split(separator: "-").first == "en" else {
      throw TTSError.unsupportedLanguage
    }
    try prepare(directory: directory, voiceID: request.voiceID)
    guard let loaded, let voice = loaded.voices[request.voiceID] else { throw TTSError.interrupted }
    let chunks = WoofTextPreparation.chunks(request.text)
    guard !chunks.isEmpty else { throw TTSError.invalidRequest }
    let initialSeed = seed ?? UInt32.random(in: .min ... .max)
    for (index, text) in chunks.enumerated() {
      try Task.checkCancellation()
      loaded.decoder.reset()
      defer { loaded.decoder.reset() }
      do {
        try loaded.generator.stream(text: text, voice: voice, seed: initialSeed &+ UInt32(index)) {
          latents in
          try Task.checkCancellation()
          let samples = try loaded.decoder.decode(latents * loaded.deviation + loaded.mean)
          guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite && abs($0) <= 8 }) else {
            throw TTSError.invalidAudio
          }
          try receive(samples)
        }
      } catch is WoofModelError { throw TTSError.invalidAudio }
    }
  }

  private func load(_ directory: URL) throws -> Loaded {
    let url = directory.appendingPathComponent("woof_int8.npz")
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard let size, size > 0, size <= WoofTensorArchive.Limits().maximumArchiveBytes else {
      throw WoofModelError.archiveLimit
    }
    let arrays = try WoofTensorArchive(data: Data(contentsOf: url, options: .mappedIfSafe)).arrays()
    guard let tree = arrays["__tree__"] else { throw WoofModelError.missingTensor("__tree__") }
    let configuration = try JSONDecoder().decode(
      WoofConfiguration.self, from: Data(tree.unicodeString().utf8))
    try configuration.validate()
    let weights = WoofWeights(arrays: arrays)
    let latentShape = [configuration.speech.transformer.latentDimensions]
    let mean = try weights.tensor(configuration.mean, shape: latentShape)
    let deviation = try weights.tensor(configuration.standardDeviation, shape: latentShape)
    let voices = try configuration.voices.mapValues { reference in
      let voice = try weights.tensor(reference)
      guard voice.ndim == 2, voice.dim(0) <= 64,
        voice.dim(1) == configuration.speech.transformer.dimensions
      else {
        throw WoofModelError.invalidTensor(reference.name)
      }
      eval(voice)
      return voice
    }
    return try Loaded(
      directory: directory,
      generator: WoofLatentGenerator(configuration: configuration, weights: weights),
      decoder: WoofAudioDecoder(
        configuration: configuration.decoder, weights: weights,
        latentDimensions: configuration.speech.transformer.latentDimensions),
      mean: mean, deviation: deviation, voices: voices)
  }
}
