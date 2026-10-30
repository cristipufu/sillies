import CryptoKit
import Foundation
import XCTest

@testable import SilliesModelStore

struct ModelUpdateFixture {
  static let firstRevision = String(repeating: "a", count: 40)
  static let secondRevision = String(repeating: "b", count: 40)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("model-update-\(UUID())")
  let original: SpeechModelManifest
  let candidate: SpeechModelManifest
  let downloader: UpdateFixtureDownloader

  init() throws {
    let descriptor = try SpeechModelCatalog.bundled().manifest(for: "whisper-turbo").model
    let old = Data("first weights".utf8)
    let new = Data("new compatible weights".utf8)
    let originalArtifact = Self.artifact(data: old, revision: Self.firstRevision)
    let candidateArtifact = Self.artifact(data: new, revision: Self.secondRevision)
    original = .init(
      model: descriptor.revised(to: Self.firstRevision), artifacts: [originalArtifact])
    candidate = .init(
      model: descriptor.revised(to: Self.secondRevision), artifacts: [candidateArtifact])
    downloader = UpdateFixtureDownloader(data: [
      originalArtifact.sha256: old, candidateArtifact.sha256: new,
    ])
  }

  static func artifact(
    data: Data, revision: String, repository: String = "fixture/weights",
    path: String = "Encoder.mlmodelc/weights/weight.bin"
  ) -> ModelArtifact {
    .init(
      path: path,
      url: URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")!,
      byteCount: Int64(data.count),
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }

  static func metadata(revision: String, artifacts: [ModelArtifact]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "sha": revision,
      "siblings": artifacts.map {
        ["rfilename": $0.path, "size": $0.byteCount, "lfs": ["sha256": $0.sha256]] as [String: Any]
      },
    ])
  }

  func cleanup() {
    if FileManager.default.fileExists(atPath: root.path) {
      do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Cleanup: \(error)") }
    }
  }
}

actor UpdateFixtureDownloader: ModelDownloading {
  let data: [String: Data]
  init(data: [String: Data]) { self.data = data }
  func download(_ request: ModelDownloadRequest) async throws -> URL {
    let value = try XCTUnwrap(data[request.artifact.sha256])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try value.write(to: url)
    return url
  }
}

actor UpdateMetadataFixture: ModelMetadataFetching {
  let responses: [String: Data]
  private(set) var requests: [URL] = []
  init(responses: [String: Data]) { self.responses = responses }
  func fetch(_ url: URL, maximumBytes: Int) async throws -> Data {
    requests.append(url)
    let data = try XCTUnwrap(responses[url.absoluteString])
    XCTAssertLessThanOrEqual(data.count, maximumBytes)
    XCTAssertFalse(Thread.isMainThread)
    return data
  }
}
