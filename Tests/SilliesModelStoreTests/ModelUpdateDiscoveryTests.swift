import Foundation
import XCTest

@testable import SilliesModelStore

final class ModelUpdateDiscoveryTests: XCTestCase, @unchecked Sendable {
  func testReadmeOnlyRevisionDoesNotOfferAnUpdate() async throws {
    let fixture = try ModelUpdateFixture()
    let readme = ModelUpdateFixture.artifact(
      data: Data("new README".utf8), revision: ModelUpdateFixture.secondRevision, path: "README.md")
    let client = UpdateMetadataFixture(responses: [
      "https://huggingface.co/api/models/fixture/weights?blobs=true":
        try ModelUpdateFixture.metadata(
          revision: ModelUpdateFixture.secondRevision,
          artifacts: fixture.original.artifacts + [readme])
    ])
    let candidate = try await ModelUpdateDiscovery(client: client).candidate(for: fixture.original)
    XCTAssertNil(candidate)
  }

  func testChangedWeightsAndNewBundleSupportFilesArePinnedAndVerified() async throws {
    let fixture = try ModelUpdateFixture()
    let support = ModelUpdateFixture.artifact(
      data: Data("new metadata".utf8), revision: ModelUpdateFixture.secondRevision,
      path: "Encoder.mlmodelc/metadata.json")
    let client = UpdateMetadataFixture(responses: [
      "https://huggingface.co/api/models/fixture/weights?blobs=true":
        try ModelUpdateFixture.metadata(
          revision: ModelUpdateFixture.secondRevision,
          artifacts: fixture.candidate.artifacts + [support])
    ])
    let discovered = try await ModelUpdateDiscovery(client: client).candidate(for: fixture.original)
    let candidate = try XCTUnwrap(discovered)
    XCTAssertEqual(candidate.artifacts.count, 2)
    XCTAssertTrue(
      candidate.artifacts.allSatisfy { $0.url.path.contains(ModelUpdateFixture.secondRevision) })
    XCTAssertNotEqual(candidate.model.revision, fixture.original.model.revision)
    try candidate.validate()
    let requestCount = await client.requests.count
    XCTAssertEqual(requestCount, 1)
  }

  func testIndependentTokenizerUpdateChangesTheCombinedRevision() async throws {
    let fixture = try ModelUpdateFixture()
    let old = ModelUpdateFixture.artifact(
      data: Data("old tokenizer".utf8), revision: ModelUpdateFixture.firstRevision,
      repository: "fixture/tokenizer", path: "tokenizer.json")
    let new = ModelUpdateFixture.artifact(
      data: Data("new tokenizer".utf8), revision: ModelUpdateFixture.secondRevision,
      repository: "fixture/tokenizer", path: "tokenizer.json")
    let installed = SpeechModelManifest(
      model: fixture.original.model, artifacts: fixture.original.artifacts + [old])
    let client = UpdateMetadataFixture(responses: [
      "https://huggingface.co/api/models/fixture/weights?blobs=true":
        try ModelUpdateFixture.metadata(
          revision: ModelUpdateFixture.firstRevision, artifacts: fixture.original.artifacts),
      "https://huggingface.co/api/models/fixture/tokenizer?blobs=true":
        try ModelUpdateFixture.metadata(
          revision: ModelUpdateFixture.secondRevision, artifacts: [new]),
    ])
    let discovered = try await ModelUpdateDiscovery(client: client).candidate(for: installed)
    let candidate = try XCTUnwrap(discovered)
    XCTAssertEqual(candidate.artifacts.first, installed.artifacts.first)
    XCTAssertEqual(candidate.artifacts.last?.sha256, new.sha256)
    XCTAssertNotEqual(candidate.model.revision, installed.model.revision)
  }

  func testMissingRequiredFileRequiresAppUpdate() async throws {
    let fixture = try ModelUpdateFixture()
    let client = UpdateMetadataFixture(responses: [
      "https://huggingface.co/api/models/fixture/weights?blobs=true":
        try ModelUpdateFixture.metadata(revision: ModelUpdateFixture.secondRevision, artifacts: [])
    ])
    do {
      _ = try await ModelUpdateDiscovery(client: client).candidate(for: fixture.original)
      XCTFail("Accepted a model with missing runtime files")
    } catch ModelUpdateError.layoutChanged {}
  }
}
