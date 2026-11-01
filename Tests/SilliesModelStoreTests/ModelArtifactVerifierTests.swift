import CryptoKit
import Foundation
import XCTest

@testable import SilliesModelStore

final class ModelArtifactVerifierTests: XCTestCase, @unchecked Sendable {
  func testUnchangedFileReusesEvidenceButReplacementAndNewVerifierRehash() async throws {
    let fixture = try VerificationFixture()
    defer { fixture.cleanup() }
    var reads = 0
    let verifier = ModelArtifactVerifier { file in
      reads += 1
      return try ModelFileDigest.sha256(file)
    }
    try verifier.verify(fixture.artifact, at: fixture.file)
    try verifier.verify(fixture.artifact, at: fixture.file)
    XCTAssertEqual(reads, 1)
    try fixture.data.write(to: fixture.file, options: .atomic)
    try verifier.verify(fixture.artifact, at: fixture.file)
    XCTAssertEqual(reads, 2)
    let restarted = ModelArtifactVerifier { file in
      reads += 1
      return try ModelFileDigest.sha256(file)
    }
    try restarted.verify(fixture.artifact, at: fixture.file)
    XCTAssertEqual(reads, 3)
  }

  func testSameSizeCorruptionCannotHideByRestoringModificationTime() async throws {
    let fixture = try VerificationFixture()
    defer { fixture.cleanup() }
    let verifier = ModelArtifactVerifier()
    try verifier.verify(fixture.artifact, at: fixture.file)
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
    let modified = try XCTUnwrap(attributes[.modificationDate])
    try Data("wrong".utf8).write(to: fixture.file)
    try FileManager.default.setAttributes(
      [.modificationDate: modified], ofItemAtPath: fixture.file.path)
    XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: fixture.file))
    try fixture.data.write(to: fixture.file)
    try verifier.verify(fixture.artifact, at: fixture.file)
  }

  func testExpectedDigestIsPartOfVerificationEvidence() async throws {
    let fixture = try VerificationFixture()
    defer { fixture.cleanup() }
    let verifier = ModelArtifactVerifier()
    try verifier.verify(fixture.artifact, at: fixture.file)
    let changedManifest = ModelArtifact(
      path: fixture.artifact.path, url: fixture.artifact.url, byteCount: fixture.artifact.byteCount,
      sha256: String(repeating: "0", count: 64))
    XCTAssertThrowsError(try verifier.verify(changedManifest, at: fixture.file))
  }

  func testChangedOrReplacedFilesDuringHashingNeverBecomeVerified() async throws {
    let fixture = try VerificationFixture()
    defer { fixture.cleanup() }
    for options: Data.WritingOptions in [[], .atomic] {
      try fixture.data.write(to: fixture.file)
      let verifier = ModelArtifactVerifier { file in
        let digest = try ModelFileDigest.sha256(file)
        try Data("wrong".utf8).write(to: fixture.file, options: options)
        return digest
      }
      XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: fixture.file))
    }
  }

  func testCachedEvidenceCannotAuthorizeSymbolicLinksOrWrongSizes() async throws {
    let fixture = try VerificationFixture()
    defer { fixture.cleanup() }
    let verifier = ModelArtifactVerifier()
    try verifier.verify(fixture.artifact, at: fixture.file)
    let link = fixture.directory.appendingPathComponent("linked.bin")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.file)
    XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: link))
    XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: fixture.directory))
    try Data("truncated".utf8).write(to: fixture.file)
    XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: fixture.file))
  }

  func testCancellationIsObservedEvenWhenFileWasAlreadyVerified() async throws {
    try await Task {
      let fixture = try VerificationFixture()
      defer { fixture.cleanup() }
      let verifier = ModelArtifactVerifier()
      try verifier.verify(fixture.artifact, at: fixture.file)
      withUnsafeCurrentTask { $0?.cancel() }
      XCTAssertThrowsError(try verifier.verify(fixture.artifact, at: fixture.file)) { error in
        XCTAssertTrue(error is CancellationError)
      }
    }.value
  }
}

private struct VerificationFixture {
  let directory: URL
  let file: URL
  let data = Data("model".utf8)
  let artifact: ModelArtifact

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appendingPathComponent("weights.bin")
    artifact = .init(
      path: "weights.bin", url: file, byteCount: Int64(data.count),
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    try data.write(to: file)
  }

  func cleanup() {
    do { try FileManager.default.removeItem(at: directory) } catch {
      XCTFail("Verification fixture cleanup failed: \(error)")
    }
  }
}
