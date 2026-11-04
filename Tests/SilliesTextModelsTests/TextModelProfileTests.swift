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

@Test func nativeRuntimeCapabilitiesAreExplicitAndRejectUnknownPolicies() throws {
  let catalog = try TextModelCatalog.bundled()
  let cached = catalog.manifests.filter {
    $0.model.profile.runtimePolicy.conversationCache == .nativeSession
  }
  #expect(
    cached.map(\.modelID) == [
      "gemma-4-e4b", "granite-4.2-3b", "granite-4.2-8b", "ministral-3-8b",
      "nemotron-3.5-bolt-e4b",
    ])
  let snapshots = catalog.manifests.filter {
    $0.model.profile.runtimePolicy.conversationCache == .prefixSnapshot
  }
  #expect(
    snapshots.map(\.modelID) == [
      "gemma-4-26b-a4b", "lfm-2.5-2.6b", "lfm-2.5-24b-a2b", "qwen-3.5-2b", "qwen-3.5-4b",
    ])
  #expect(
    snapshots.allSatisfy { $0.model.profile.runtimePolicy.prefixSnapshot?.maximumTokens == 2_048 })
  #expect(
    snapshots.map { $0.model.profile.runtimePolicy.prefixSnapshot?.maximumBytes } == [
      384 * 1_024 * 1_024, 64 * 1_024 * 1_024, 128 * 1_024 * 1_024,
      96 * 1_024 * 1_024, 192 * 1_024 * 1_024,
    ])
  let normalized = catalog.manifests.filter {
    $0.model.profile.runtimePolicy.chatTemplate == .mistral3
  }
  #expect(normalized.map(\.modelID) == ["ministral-3-8b"])
  #expect(throws: (any Error).self) {
    _ = try editedProfile {
      $0["runtime"] = ["conversationCache": "guess", "chatTemplate": "checkpoint"]
    }
  }
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

@Test func prefixSnapshotsRequireExplicitBoundedPerModelPolicy() throws {
  for configuration: [String: Any] in [
    ["conversationCache": "prefixSnapshot", "chatTemplate": "checkpoint"],
    [
      "conversationCache": "prefixSnapshot", "chatTemplate": "checkpoint",
      "prefixSnapshot": ["maximumTokens": 0, "maximumBytes": 1_024],
    ],
    [
      "conversationCache": "prefixSnapshot", "chatTemplate": "checkpoint",
      "prefixSnapshot": ["maximumTokens": 64, "maximumBytes": -1],
    ],
    [
      "conversationCache": "prefixSnapshot", "chatTemplate": "checkpoint",
      "prefixSnapshot": ["maximumTokens": Int.max, "maximumBytes": 1_024],
    ],
    [
      "conversationCache": "nativeSession", "chatTemplate": "checkpoint",
      "prefixSnapshot": ["maximumTokens": 64, "maximumBytes": 1_024],
    ],
  ] {
    let manifest = try editedProfile { $0["runtime"] = configuration }
    #expect(throws: ModelStoreError.self) { try manifest.validate() }
  }
  let valid = try editedProfile {
    $0["runtime"] = [
      "conversationCache": "prefixSnapshot", "chatTemplate": "checkpoint",
      "prefixSnapshot": ["maximumTokens": 64, "maximumBytes": 1_024],
    ]
  }
  try valid.validate()
  #expect(valid.model.profile.runtimePolicy.prefixSnapshot?.maximumTokens == 64)
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
