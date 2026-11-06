import Foundation
import SilliesCore
import Testing

@testable import SilliesModelStore

@Test func calibrationRequiresReviewedQualityAndMatchingRuntimeIdentity() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  let helper = directory.appendingPathComponent("helper")
  try Data("runtime one".utf8).write(to: helper)
  let baseline = try #require(try TextModelCatalog.bundled().manifests.first)
  let identity = try TextCalibrationIdentity.capture(baseline, helper: helper)
  let store = TextCalibrationStore(
    directory: directory.appendingPathComponent("receipts"), helper: helper)
  #expect(try await store.resolve(baseline) == baseline)
  let evidence = TextCalibrationReceipt.Evidence(
    baselineHash: String(repeating: "a", count: 64),
    candidateHash: String(repeating: "b", count: 64),
    corpusHash: String(repeating: "c", count: 64), comparedCases: 6, repeats: 2,
    reviewedTurns: 12, totalTurns: 12, newFailures: 0,
    baselineFirstTextMedian: 2, candidateFirstTextMedian: 1)
  let qualified = TextCalibrationReceipt(
    version: 1, identity: identity, chunkTokens: 128, evidence: evidence)
  #expect(qualified.isQualified)
  try await store.install(qualified, for: baseline)
  #expect(try await store.resolve(baseline).model.profile.prefill.chunkTokens == 128)
  // A different chunk-only baseline is still a different reviewed profile.
  let changed = try baseline.processingPrefill(inChunksOf: 256)
  #expect(try await store.resolve(changed) == changed)
  try Data("runtime two".utf8).write(to: helper, options: .atomic)
  #expect(try await store.resolve(baseline) == baseline)
  await #expect(throws: ModelStoreError.self) { try await store.install(qualified, for: baseline) }
}

@Test func calibrationRefusesIncompleteRegressedOrInvalidEvidence() throws {
  let model = try #require(try TextModelCatalog.bundled().manifests.first)
  let identity = TextCalibrationIdentity(
    modelID: model.modelID, revision: model.revision,
    profile: model.model.profile, helperSHA256: String(repeating: "a", count: 64),
    hardware: .init(processor: "Apple M4", memoryBytes: 16_000_000_000, operatingSystem: "test"))
  let evidence = TextCalibrationReceipt.Evidence(
    baselineHash: String(repeating: "b", count: 64),
    candidateHash: String(repeating: "c", count: 64), corpusHash: String(repeating: "d", count: 64),
    comparedCases: 6, repeats: 2, reviewedTurns: 12, totalTurns: 12, newFailures: 0,
    baselineFirstTextMedian: 2, candidateFirstTextMedian: 1)
  let receipt = TextCalibrationReceipt(
    version: 1, identity: identity, chunkTokens: 128, evidence: evidence)
  let encoded = try JSONEncoder().encode(receipt)
  for (key, value) in [
    ("comparedCases", 0), ("repeats", 1), ("reviewedTurns", 11), ("newFailures", 1),
    ("candidateFirstTextMedian", 3), ("totalTurns", 6), ("comparedCases", Int.max),
  ] {
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var proof = try #require(json["evidence"] as? [String: Any])
    proof[key] = value
    json["evidence"] = proof
    let invalid = try JSONDecoder().decode(
      TextCalibrationReceipt.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!invalid.isQualified)
  }
  #expect(
    !TextCalibrationReceipt(
      version: 1, identity: identity, chunkTokens: Int.max, evidence: evidence
    ).isQualified)
}
