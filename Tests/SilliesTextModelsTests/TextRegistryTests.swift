import CryptoKit
import Foundation
import SilliesInference
import Testing

@testable import SilliesModelStore
@testable import SilliesTextModels

@Test func speechPreemptsTextAndResumesWithoutOverlappingInference() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  let activity = InferenceActivity()
  let engine = ProbeTextModel()
  let registry = try TextModelRegistry(
    store: store, providers: [ProbeProvider(model: engine)], activity: activity)
  let generation = Task { try await registry.generate(fixture.request, using: fixture.manifest) }
  try await waitFor { await engine.calls == 1 }
  await activity.beginSpeech()
  #expect(await engine.stops > 0)
  #expect(await engine.calls == 1)
  await activity.endSpeech()
  #expect(try await generation.value == "Ștefan trimite raportul mâine.")
  #expect(await engine.maximumActive == 1)
  await registry.stop()
  try await store.remove(fixture.manifest)
}

@Test func cancelledTextReleasesItsLeaseAndDoesNotRestart() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  let engine = ProbeTextModel()
  let registry = try TextModelRegistry(
    store: store, providers: [ProbeProvider(model: engine)], activity: InferenceActivity())
  let generation = Task { try await registry.generate(fixture.request, using: fixture.manifest) }
  try await waitFor { await engine.calls == 1 }
  generation.cancel()
  await #expect(throws: CancellationError.self) { try await generation.value }
  await registry.stop()
  #expect(await engine.calls == 1)
  try await store.remove(fixture.manifest)
}

@Test func missingModelsNeverDownloadImplicitlyAndDuplicateProvidersAreRejected() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  let provider = ProbeProvider(model: ProbeTextModel())
  #expect(throws: (any Error).self) {
    try TextModelRegistry(store: store, providers: [provider, provider])
  }
  let registry = try TextModelRegistry(store: store, providers: [provider])
  await #expect(throws: ModelStoreError.self) {
    try await registry.generate(fixture.request, using: fixture.manifest)
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
}

@Test func suspendedTextCannotStartWork() async throws {
  let fixture = try TextFixture()
  let registry = try TextModelRegistry(store: ModelStore(root: fixture.root), providers: [])
  await registry.suspend()
  await #expect(throws: TextModelError.self) {
    try await registry.generate(fixture.request, using: fixture.manifest)
  }
}

private struct ProbeProvider: TextModelProvider {
  let id = "mlx"
  let model: ProbeTextModel
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel {
    model
  }
}

private actor ProbeTextModel: PreparedTextModel {
  private(set) var calls = 0
  private(set) var stops = 0
  private(set) var maximumActive = 0
  private var active = 0
  func generate(_ request: TextGenerationRequest) async throws -> String {
    calls += 1
    active += 1
    maximumActive = max(maximumActive, active)
    defer { active -= 1 }
    if calls == 1 { try await Task.sleep(for: .seconds(5)) }
    return "Ștefan trimite raportul mâine."
  }
  func stop() { stops += 1 }
}

private struct FixtureDownloader: ModelDownloading {
  func download(_ request: ModelDownloadRequest) async throws -> URL {
    let file = request.resumeFile.appendingPathExtension("fixture")
    try Data("hello".utf8).write(to: file)
    request.progress(5)
    return file
  }
}

private struct TextFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-text-test-\(UUID())")
  let manifest: TextModelManifest
  let request = TextGenerationRequest(
    instructions: "Summarize", prompt: "Ștefan trimite raportul mâine.", maximumTokens: 50)
  init() throws {
    let bundled = try #require(TextModelCatalog.bundled().manifests.first)
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(bundled)) as? [String: Any])
    var model = try #require(object["model"] as? [String: Any])
    model["minimumMemoryGB"] = 1
    object["model"] = model
    object["artifacts"] = [
      [
        "path": "weights.bin",
        "url": "https://huggingface.co/test/model/resolve/\(bundled.revision)/weights.bin",
        "byteCount": 5,
        "sha256": SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined(),
      ]
    ]
    manifest = try JSONDecoder().decode(
      TextModelManifest.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func remove() {
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    do { try FileManager.default.removeItem(at: root) } catch {
      Issue.record("Fixture cleanup: \(error)")
    }
  }
}

private func waitFor(_ predicate: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await predicate()) {
    guard ContinuousClock.now < deadline else { throw TextModelError.interrupted }
    try await Task.sleep(for: .milliseconds(5))
  }
}
