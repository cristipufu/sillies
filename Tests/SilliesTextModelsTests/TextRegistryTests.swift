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

@Test func activeConversationRetainsTextUntilItEndsAndPressureCanEvictIt() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  let model = RetainedTextProbe()
  let registry = try TextModelRegistry(
    store: store, providers: [RetainedTextProvider(model: model)], activity: InferenceActivity(),
    idleDuration: .milliseconds(10))
  let lifetime = TextModelLifetime()
  await registry.retain(for: lifetime)
  _ = try await registry.generate(fixture.request, using: fixture.manifest)
  try await Task.sleep(for: .milliseconds(60))
  #expect(await model.stops == 0)
  await lifetime.end()
  try await waitFor { await model.stops == 1 }
  let another = TextModelLifetime()
  await registry.retain(for: another)
  _ = try await registry.generate(fixture.request, using: fixture.manifest)
  await registry.setRetention(.memoryPressure)
  #expect(await model.stops == 2)
  await registry.stop()
}

private struct RetainedTextProvider: TextModelProvider {
  let id = "mlx"
  let model: RetainedTextProbe
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel {
    await model.prepared(contextTokens: configuration.contextTokens)
    return model
  }
}

private actor RetainedTextProbe: PreparedTextModel {
  private(set) var stops = 0
  private(set) var releasedConversations: [UUID] = []
  private(set) var preparedContexts: [Int] = []
  func prepared(contextTokens: Int) { preparedContexts.append(contextTokens) }
  func generate(_ request: TextGenerationRequest) async throws -> String { "Ready" }
  func stop() { stops += 1 }
  func releaseConversation(_ sessionID: UUID) { releasedConversations.append(sessionID) }
}

@Test func endingOneConversationReleasesItsNativeStateWhileAnotherRetainsTheModel() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  let model = RetainedTextProbe()
  let registry = try TextModelRegistry(
    store: store, providers: [RetainedTextProvider(model: model)], activity: InferenceActivity())
  let first = TextModelLifetime()
  let second = TextModelLifetime()
  await registry.retain(for: first)
  await registry.retain(for: second)
  _ = try await registry.generate(fixture.request.inSession(first.id), using: fixture.manifest)
  await first.end()
  #expect(await model.releasedConversations == [first.id])
  #expect(await model.stops == 0)
  await second.end()
  #expect(await model.releasedConversations == [first.id, second.id])
  await registry.stop()
}

@Test func changingAProfileReleasesTheOldRuntimeWithoutRedownloadingItsWeights() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  var encoded = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.manifest)) as? [String: Any])
  var descriptor = try #require(encoded["model"] as? [String: Any])
  var profile = try #require(descriptor["profile"] as? [String: Any])
  var context = try #require(profile["context"] as? [String: Any])
  let updatedCapacity = fixture.manifest.model.contextTokens + 1_024
  context["workingTokens"] = updatedCapacity
  profile["context"] = context
  descriptor["profile"] = profile
  encoded["model"] = descriptor
  let changed = try JSONDecoder().decode(
    TextModelManifest.self, from: JSONSerialization.data(withJSONObject: encoded))
  try changed.validate()
  let model = RetainedTextProbe()
  let registry = try TextModelRegistry(
    store: store, providers: [RetainedTextProvider(model: model)], activity: InferenceActivity())
  _ = try await registry.generate(fixture.request, using: fixture.manifest)
  _ = try await registry.generate(fixture.request, using: fixture.manifest)
  #expect(await model.preparedContexts.count == 1)
  _ = try await registry.generate(fixture.request, using: changed)
  #expect(await model.preparedContexts == [fixture.manifest.model.contextTokens, updatedCapacity])
  #expect(await model.stops == 1)
  await registry.stop()
  try await store.remove(changed)
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

private actor StreamingPreemptionProbe: PreparedTextModel {
  var calls = 0
  func generate(_ request: TextGenerationRequest) async throws -> String { "Hello" }
  func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    calls += 1
    try await receive("Already delivered. ")
    try await Task.sleep(for: .seconds(5))
    return .init(text: "Already delivered. The rest.")
  }
  func stop() {}
}
private struct StreamingProbeProvider: TextModelProvider {
  let id = "mlx"
  let model: StreamingPreemptionProbe
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel {
    model
  }
}

@Test func preemptedTextStreamNeverAutomaticallyReplaysADeliveredPrefix() async throws {
  let fixture = try TextFixture()
  defer { fixture.remove() }
  let store = ModelStore(root: fixture.root, downloader: FixtureDownloader())
  try await store.install(fixture.manifest) { _ in }
  let activity = InferenceActivity()
  let model = StreamingPreemptionProbe()
  let registry = try TextModelRegistry(
    store: store, providers: [StreamingProbeProvider(model: model)], activity: activity)
  let generation = Task {
    try await registry.stream(fixture.request, using: fixture.manifest, receive: { _ in })
  }
  try await waitFor { await model.calls == 1 }
  await activity.beginSpeech()
  await activity.endSpeech()
  await #expect(throws: CancellationError.self) { try await generation.value }
  #expect(await model.calls == 1)
  await registry.stop()
  try await store.remove(fixture.manifest)
}
