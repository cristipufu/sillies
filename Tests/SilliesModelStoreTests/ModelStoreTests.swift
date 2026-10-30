import CryptoKit
import Foundation
import XCTest

@testable import SilliesModelStore

final class ModelStoreTests: XCTestCase, @unchecked Sendable {
  func testReplacementAndRemovalPublishOnlyCompleteInstallations() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.manifest) { _ in }
    try await store.install(fixture.manifest) { _ in }
    let ready = try await store.isInstalled(fixture.manifest)
    XCTAssertTrue(ready)
    try await store.remove(fixture.manifest)
    let removed = try await store.isInstalled(fixture.manifest)
    XCTAssertFalse(removed)
  }

  func testCancellationNeverPublishesAnIncompleteModel() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let downloader = SuspendedDownloader()
    let store = ModelStore(root: fixture.root, downloader: downloader)
    let installation = Task { try await store.install(fixture.manifest) { _ in } }
    while await downloader.started == false { await Task.yield() }
    installation.cancel()
    do {
      try await installation.value
      XCTFail("Cancelled installation succeeded")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    let installed = try await store.isInstalled(fixture.manifest)
    XCTAssertFalse(installed)
    try await store.remove(fixture.manifest)
  }
  func testBundledCatalogIsPinnedAndIncludesRomanian() throws {
    let catalog = try SpeechModelCatalog.bundled()
    XCTAssertEqual(catalog.manifests.count, 3)
    for manifest in catalog.manifests {
      if !manifest.model.isDiarizationModel {
        XCTAssertTrue(manifest.model.capabilities.languages.contains("ro"))
        XCTAssertTrue(manifest.model.capabilities.languages.contains("en"))
      }
      for artifact in manifest.artifacts {
        let components = artifact.url.pathComponents
        let revision = try XCTUnwrap(components.firstIndex(of: "resolve")).advanced(by: 1)
        XCTAssertEqual(components[revision].count, 40)
        XCTAssertTrue(components[revision].allSatisfy(\.isHexDigit))
      }
    }
  }

  func testVerifiedInstallationIsOfflineAndLeaseProtectsRemoval() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.manifest) { _ in }
    let installed = try await store.isInstalled(fixture.manifest)
    XCTAssertTrue(installed)
    let lease = try await store.acquire(fixture.manifest)
    XCTAssertEqual(
      try Data(contentsOf: lease.directory.appendingPathComponent("weights.bin")), fixture.data)
    do {
      try await store.remove(fixture.manifest)
      XCTFail("Removed active model")
    } catch ModelStoreError.inUse {} catch { XCTFail("Unexpected error: \(error)") }
    let calls = await fixture.downloader.calls
    XCTAssertEqual(calls, 1)
    withExtendedLifetime(lease) {}
  }

  func testCorruptDownloadNeverBecomesInstalledAndRetryWorks() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    await fixture.downloader.setData(Data("wrong".utf8))
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    do {
      try await store.install(fixture.manifest) { _ in }
      XCTFail("Accepted corrupt file")
    } catch ModelStoreError.invalidArtifact {} catch { XCTFail("Unexpected error: \(error)") }
    let installed = try await store.isInstalled(fixture.manifest)
    XCTAssertFalse(installed)
    await fixture.downloader.setData(fixture.data)
    try await store.install(fixture.manifest) { _ in }
    let ready = try await store.isInstalled(fixture.manifest)
    XCTAssertTrue(ready)
    let offMain = await fixture.downloader.offMain
    XCTAssertTrue(offMain)
  }

  func testTamperedInstallationFailsVerificationBeforeInference() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.manifest) { _ in }
    let location = fixture.root.appendingPathComponent(fixture.manifest.model.id)
      .appendingPathComponent(fixture.manifest.model.revision).appendingPathComponent("weights.bin")
    try Data("wrong".utf8).write(to: location)
    do {
      _ = try await store.acquire(fixture.manifest)
      XCTFail("Accepted tampered weights")
    } catch ModelStoreError.invalidArtifact {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testTraversalAndSymbolicLinksCannotEscapeStore() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    XCTAssertFalse(ModelFiles.isSafeRelativePath("../outside"))
    XCTAssertFalse(ModelFiles.isSafeRelativePath("/tmp/outside"))
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: fixture.root.appendingPathComponent("escape"),
      withDestinationURL: fixture.root.deletingLastPathComponent())
    XCTAssertThrowsError(
      try ModelFiles.child("escape/weights", in: fixture.root.resolvingSymlinksInPath()))
  }
}

private actor SuspendedDownloader: ModelDownloading {
  private(set) var started = false
  func download(_ request: ModelDownloadRequest) async throws -> URL {
    started = true
    try await Task.sleep(for: .seconds(5))
    throw CancellationError()
  }
}

private struct Fixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-model-test-\(UUID())")
  let data = Data("model".utf8)
  let manifest: SpeechModelManifest
  let downloader: FixtureDownloader

  init() throws {
    let descriptor = try SpeechModelCatalog.bundled().manifest(for: "whisper-turbo").model
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    manifest = SpeechModelManifest(
      model: descriptor,
      artifacts: [
        .init(
          path: "weights.bin",
          url: URL(
            string:
              "https://huggingface.co/test/model/resolve/0123456789012345678901234567890123456789/weights.bin"
          )!, byteCount: Int64(data.count), sha256: hash)
      ])
    downloader = FixtureDownloader(data: data)
  }

  func cleanup() {
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    do { try FileManager.default.removeItem(at: root) } catch {
      XCTFail("Cleanup failed: \(error)")
    }
  }
}

private actor FixtureDownloader: ModelDownloading {
  var data: Data
  private(set) var calls = 0
  private(set) var offMain = true
  init(data: Data) { self.data = data }
  func setData(_ data: Data) { self.data = data }
  func download(_ request: ModelDownloadRequest) async throws -> URL {
    calls += 1
    offMain = offMain && !Thread.isMainThread
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: file)
    request.progress(Int64(data.count))
    return file
  }
}
