import Foundation
import NaturalLanguage
import SilliesCore

/// Helper-confined Natural Language objects; no SDK state crosses the process boundary.
actor AppleMemoryEmbedding: PreparedEmbeddingModel {
  // Apple exposes six model groups. An empty discovery filter returns no models on macOS.
  private static let scripts: [NLScript] = [
    .latin, .cyrillic, .simplifiedChinese, .arabic, .devanagari, .thai,
  ]
  private let models = scripts.compactMap { NLContextualEmbedding(script: $0) }
  private var loaded: NLContextualEmbedding?
  var identity: String {
    "apple-contextual-mean-v1/"
      + models.map {
        "\($0.modelIdentifier):\($0.revision):\($0.hasAvailableAssets)"
      }.sorted().joined(separator: ";")
  }
  func embed(_ input: MemoryEmbeddingInput) throws -> MemoryEmbedding? {
    guard let language = NLLanguageRecognizer.dominantLanguage(for: input.text),
      let model = models.first(where: { $0.languages.contains(language) && $0.hasAvailableAssets })
    else { return nil }
    if loaded !== model {
      loaded?.unload()
      try model.load()
      loaded = model
    }
    let result = try model.embeddingResult(for: input.text, language: language)
    guard result.sequenceLength < model.maximumSequenceLength else { return nil }
    guard (1...MemoryEmbedding.maximumDimensions).contains(model.dimension) else {
      throw MemoryEmbeddingError.invalidVector
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
    guard !invalidVector else { throw MemoryEmbeddingError.invalidVector }
    guard count > 0 else { return nil }
    return try MemoryEmbedding(
      space: "\(model.modelIdentifier):\(model.revision):mean-v1",
      values: sum.map { Float($0 / Double(count)) })
  }
}
