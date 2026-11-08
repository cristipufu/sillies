import Foundation
import NaturalLanguage
import SilliesCore
import SilliesSearchModels

/// Helper-confined Natural Language objects; no SDK state crosses the process boundary.
actor AppleSearchEmbedding: PreparedEmbeddingModel {
  // Apple exposes six model groups. An empty discovery filter returns no models on macOS.
  private static let scripts: [NLScript] = [
    .latin, .cyrillic, .simplifiedChinese, .arabic, .devanagari, .thai,
  ]
  private let models = scripts.compactMap { NLContextualEmbedding(script: $0) }
  private var loaded: NLContextualEmbedding?
  var identity: String {
    "apple-contextual-mean-v1/\(EmbeddingPreparation.revision)/"
      + models.map {
        "\($0.modelIdentifier):\($0.revision):\($0.hasAvailableAssets)"
      }.sorted().joined(separator: ";")
  }
  func embed(_ input: SearchEmbeddingInput) async throws -> SearchEmbedding? {
    guard let language = NLLanguageRecognizer.dominantLanguage(for: input.text) else { return nil }
    // Resolve language on the full input; short continuation fragments may be ambiguous by themselves.
    let languageID = language.rawValue
    return try await EmbeddingPreparation.embed(input) { [self] part in
      try await encode(part, languageID: languageID)
    }
  }

  private func encode(_ input: SearchEmbeddingInput, languageID: String) throws
    -> EmbeddingChunkResult
  {
    let language = NLLanguage(rawValue: languageID)
    guard
      let model = models.first(where: { $0.languages.contains(language) && $0.hasAvailableAssets })
    else { return .unsupported }
    if loaded !== model {
      loaded?.unload()
      try model.load()
      loaded = model
    }
    let result = try model.embeddingResult(for: input.text, language: language)
    guard result.sequenceLength < model.maximumSequenceLength else { return .exceedsCapacity }
    guard (1...SearchEmbedding.maximumDimensions).contains(model.dimension) else {
      throw SearchEmbeddingError.invalidVector
    }
    var sum = [Double](repeating: 0, count: model.dimension)
    var count = 0
    var invalidVector = false
    result.enumerateTokenVectors(in: input.text.startIndex..<input.text.endIndex) { vector, _ in
      guard vector.count == sum.count else {
        invalidVector = true
        return false
      }
      for index in sum.indices { sum[index] += vector[index] }
      count += 1
      return true
    }
    guard !invalidVector else { throw SearchEmbeddingError.invalidVector }
    guard count > 0 else { return .unsupported }
    return try .embedded(
      EmbeddingChunk(
        space:
          "\(model.modelIdentifier):\(model.revision):mean-v1/\(EmbeddingPreparation.revision)",
        mean: sum.map { Float($0 / Double(count)) }, tokenCount: count))
  }
}
