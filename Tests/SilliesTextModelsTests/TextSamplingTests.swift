import Foundation
import SilliesCore
import Testing

@testable import SilliesModelStore
@testable import SilliesTextModels

@Test func conversationSamplingSurvivesNativePreparationTransport() throws {
  let sampling = try JSONDecoder().decode(
    TextModelSampling.self,
    from: Data(#"{"temperature":0.1,"topP":1,"topK":50,"repetitionPenalty":1.05}"#.utf8))
  let preparation = TextModelPreparation(
    directory: URL(fileURLWithPath: "/fixture"), contextTokens: 4096, memoryLimitBytes: 1,
    conversationSampling: sampling)
  let restored = try JSONDecoder().decode(
    TextModelPreparation.self, from: JSONEncoder().encode(preparation))
  #expect(restored.conversationSampling == sampling)
  #expect(sampling.isValid)
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
  model["conversationSampling"] = sampling
  object["model"] = model
  let manifest = try JSONDecoder().decode(
    TextModelManifest.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(throws: ModelStoreError.self) { try manifest.validate() }
}
