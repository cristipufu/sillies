import Foundation
import SilliesTextModels

/// Hard checkpoint rules are independent of the app's per-task sampling choices.
struct CheckpointGenerationConstraints: Sendable {
  static let unconstrained = Self(suppressedTokens: [])
  private static let maximumMetadataBytes = 1_024 * 1_024
  private static let maximumSuppressedTokens = 4_096
  let suppressedTokens: [Int32]

  private struct Generation: Decodable {
    let suppressTokens: [Int]?
    enum CodingKeys: String, CodingKey { case suppressTokens = "suppress_tokens" }
  }

  private struct Model: Decodable {
    struct Text: Decodable {
      let vocabularySize: Int?
      enum CodingKeys: String, CodingKey { case vocabularySize = "vocab_size" }
    }
    let vocabularySize: Int?
    let text: Text?
    enum CodingKeys: String, CodingKey {
      case vocabularySize = "vocab_size"
      case text = "text_config"
    }
  }

  static func load(from directory: URL) throws -> Self {
    let generation = try TextInferenceJSON.readIfPresent(
      Generation.self, from: directory.appendingPathComponent("generation_config.json"),
      maximumBytes: maximumMetadataBytes)
    guard let tokens = generation?.suppressTokens, !tokens.isEmpty else { return .unconstrained }
    let model = try TextInferenceJSON.read(
      Model.self, from: directory.appendingPathComponent("config.json"),
      maximumBytes: maximumMetadataBytes)
    guard let vocabulary = model.text?.vocabularySize ?? model.vocabularySize else {
      throw TextModelError.invalidResponse
    }
    return try validated(tokens: tokens, vocabularySize: vocabulary)
  }

  static func validated(tokens: [Int], vocabularySize: Int) throws -> Self {
    guard vocabularySize > 0, vocabularySize <= Int(Int32.max),
      tokens.count <= maximumSuppressedTokens,
      tokens.allSatisfy({ $0 >= 0 && $0 < vocabularySize })
    else { throw TextModelError.invalidResponse }
    let unique = Set(tokens).sorted()
    guard unique.count < vocabularySize else { throw TextModelError.invalidResponse }
    return Self(suppressedTokens: unique.map { Int32($0) })
  }
}
