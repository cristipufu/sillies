import Foundation
import SilliesCore
import Testing

@testable import SilliesModelStore

@Test(arguments: [0, -1, Int.max])
func modelProfileRejectsInvalidWorkingCapacity(_ capacity: Int) throws {
  let manifest = try editedProfile { profile in
    var context = try #require(profile["context"] as? [String: Any])
    context["workingTokens"] = capacity
    profile["context"] = context
  }
  #expect(throws: ModelStoreError.self) { try manifest.validate() }
}

@Test(arguments: [0, -64])
func modelProfileRejectsInvalidPrefillOverride(_ chunk: Int) throws {
  let manifest = try editedProfile { $0["prefill"] = ["chunkTokens": chunk] }
  #expect(throws: ModelStoreError.self) { try manifest.validate() }
}

@Test func modelProfilePreservesRuntimeSelectedPrefillAndAllowsReviewedLargerContexts() throws {
  let manifest = try editedProfile { profile in
    profile["context"] = ["maximumTokens": 32_768, "workingTokens": 16_384]
    profile["prefill"] = [:]
  }
  try manifest.validate()
  #expect(manifest.model.contextTokens == 16_384)
  #expect(manifest.model.profile.prefill.chunkTokens == nil)
}

@Test func modelProfileRequiresProvenanceAndFitsReasoningWithinCapacity() throws {
  let missingEvidence = try editedProfile {
    $0["evidence"] = ["sources": [], "runtimeRevision": "", "rationale": ""]
  }
  #expect(throws: ModelStoreError.self) { try missingEvidence.validate() }
  let overflow = try editedProfile { profile in
    var generation = try #require(profile["generation"] as? [String: Any])
    var summary = try #require(generation["summary"] as? [String: Any])
    summary["reasoningTokens"] = Int.max
    generation["summary"] = summary
    profile["generation"] = generation
  }
  #expect(throws: ModelStoreError.self) { try overflow.validate() }
}

private func editedProfile(_ edit: (inout [String: Any]) throws -> Void) throws -> TextModelManifest
{
  let original = try #require(TextModelCatalog.bundled().manifests.first)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
  var model = try #require(object["model"] as? [String: Any])
  var profile = try #require(model["profile"] as? [String: Any])
  try edit(&profile)
  model["profile"] = profile
  object["model"] = model
  return try JSONDecoder().decode(
    TextModelManifest.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func modelTaskAllowanceCapsRequestsWithoutChangingSmallerFeatureBudgets() {
  let task = TextGenerationProfile.Task(
    outputTokens: 320, reasoningTokens: 1_024,
    sampling: .init(temperature: 0, topP: 1, topK: 0, repetitionPenalty: nil),
    repetitionContextTokens: 0)
  #expect(task.generationTokens(for: 100) == 1_124)
  #expect(task.generationTokens(for: Int.max) == 1_344)
  #expect(task.generationTokens(for: 0) == nil)
}
