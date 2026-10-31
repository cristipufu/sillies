import Foundation
import SilliesCore
import SilliesDiarizationNemotron
import SilliesModelStore
import SilliesSpeechParakeet
import SilliesSpeechWhisper
import Testing

@testable import SilliesApp

/// Opt-in validation with existing local weights. No devices, downloads, or live app storage.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_VALIDATE_MODEL_UPDATE"] == "1"))
func nativeModelUpdateValidatesBeforeActivationAndCanRollBack() async throws {
  let environment = ProcessInfo.processInfo.environment
  let id = try #require(environment["SILLIES_STT_MODEL"])
  let sourceRoot = try #require(environment["SILLIES_STT_STORE"])
  let original = try SpeechModelCatalog.bundled().manifest(for: id)
  let sourceStore = ModelStore(root: URL(fileURLWithPath: sourceRoot))
  let source = try await sourceStore.acquire(original)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-native-update-\(UUID())")
  defer {
    do { try FileManager.default.removeItem(at: root) } catch {
      Issue.record("Fixture cleanup: \(error)")
    }
  }
  let store = ModelStore(root: root, downloader: LocalModelCopy(source: source.directory))
  try await store.install(original) { _ in }
  let candidate = SpeechModelManifest(
    model: original.model.revised(to: "compatibility-fixture"), artifacts: original.artifacts)
  try await store.stageUpdate(candidate, replacing: original) { _ in }
  #expect(try await store.currentManifest(original) == original)
  let registry = try SpeechRuntimeRegistry(
    store: store, providers: [WhisperSpeechProvider(), ParakeetSpeechProvider()],
    diarizationProviders: [NemotronDiarizationProvider()])
  try await registry.validateAndActivate(candidate)
  #expect(try await store.currentManifest(original) == candidate)
  #expect(try await store.previousManifest(original) == original)
  try await waitForValidationLeaseRelease(registry, id: id)
  #expect(try await store.currentManifest(original) == original)
  withExtendedLifetime(source) {}
}

private func waitForValidationLeaseRelease(_ registry: SpeechRuntimeRegistry, id: String)
  async throws
{
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while true {
    do {
      try await registry.rollBack(id)
      return
    } catch ModelStoreError.inUse {
      guard ContinuousClock.now < deadline else { throw ModelStoreError.inUse }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private actor LocalModelCopy: ModelDownloading {
  let source: URL
  init(source: URL) { self.source = source }
  func download(_ request: ModelDownloadRequest) async throws -> URL {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.copyItem(
      at: source.appendingPathComponent(request.artifact.path), to: temporary)
    return temporary
  }
}
