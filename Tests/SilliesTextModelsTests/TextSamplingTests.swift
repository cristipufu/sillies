import Foundation
import SilliesCore
import Testing

@testable import SilliesModelStore
@testable import SilliesTextModels

@Test func mandatoryReasoningUsesTheSelectedModelsTaskCapacity() throws {
  let models = try TextModelCatalog.bundled().manifests.map(\.model)
  for model in models {
    let generation = model.profile.generation
    if model.reasoning == .alwaysOnThinkTags {
      #expect(generation.summary.reasoningTokens > generation.conversation.reasoningTokens)
      #expect(generation.conversation.reasoningTokens > 0)
    } else {
      #expect(generation.summary.reasoningTokens == 0)
      #expect(generation.conversation.reasoningTokens == 0)
    }
  }
}

@Test func selectedModelProfileSurvivesNativePreparationTransport() throws {
  for manifest in try TextModelCatalog.bundled().manifests {
    let preparation = TextModelPreparation(
      directory: URL(fileURLWithPath: "/fixture"), profile: manifest.model.profile,
      memoryLimitBytes: 1, reasoning: manifest.model.reasoning)
    let restored = try JSONDecoder().decode(
      TextModelPreparation.self, from: JSONEncoder().encode(preparation))
    #expect(restored.profile == manifest.model.profile)
    #expect(restored.contextTokens == manifest.model.contextTokens)
  }
}

@Test(arguments: [
  ("temperature", -0.1), ("temperature", 3), ("topP", 0), ("topP", 2),
  ("topK", -1), ("topK", 100_000), ("repetitionPenalty", 0), ("repetitionPenalty", 3),
])
func catalogRejectsInvalidSamplingBeforePreparingAModel(field: String, value: Double) throws {
  let original = try #require(TextModelCatalog.bundled().manifests.first)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
  var model = try #require(object["model"] as? [String: Any])
  var sampling: [String: Double] = [
    "temperature": 0.1, "topP": 1, "topK": 50, "repetitionPenalty": 1.05,
  ]
  sampling[field] = value
  var profile = try #require(model["profile"] as? [String: Any])
  var generation = try #require(profile["generation"] as? [String: Any])
  var conversation = try #require(generation["conversation"] as? [String: Any])
  conversation["sampling"] = sampling
  generation["conversation"] = conversation
  profile["generation"] = generation
  model["profile"] = profile
  object["model"] = model
  let manifest = try JSONDecoder().decode(
    TextModelManifest.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(throws: ModelStoreError.self) { try manifest.validate() }
}
