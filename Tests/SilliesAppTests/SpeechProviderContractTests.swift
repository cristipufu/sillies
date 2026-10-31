import Foundation
import SilliesCore
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechParakeet
import SilliesSpeechWhisper
import Testing

@testable import SilliesApp

/// Add downloaded adapters here: these contracts require no weights or microphone permission.
@Test func downloadedSpeechProvidersHonorLanguageAvailabilityAndCancellation() async throws {
  let catalog = try SpeechModelCatalog.bundled()
  for (provider, identifier): (any SpeechProvider, String) in [
    (WhisperSpeechProvider(), "whisper-turbo"), (ParakeetSpeechProvider(), "parakeet-ultra"),
  ] {
    try await verifySpeechProviderContract(
      provider, model: catalog.manifest(for: identifier).model, expectedLanguages: ["en", "ro"])
  }
}

func verifySpeechProviderContract(
  _ provider: any SpeechProvider, model: SpeechModelDescriptor, expectedLanguages: [String]
)
  async throws
{
  let missing = try await provider.languages(.init(model: model, availability: .missing))
  #expect(missing.model == model)
  #expect(missing.installed.isEmpty)
  let available = try await provider.languages(.init(model: model, availability: .installed))
  #expect(available.model == model)
  for identifier in expectedLanguages {
    #expect(available.installedLanguage(matching: identifier) != nil)
  }
  #expect(available.installedLanguage(matching: "zz") == nil)
  let canceled = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    return try await provider.prepare(.init(model: model, directory: nil))
  }
  do {
    _ = try await canceled.value
    Issue.record("A canceled provider preparation succeeded")
  } catch is CancellationError {} catch { Issue.record("Cancellation became \(error)") }
}

@Test func speechRegistryRejectsDuplicateProvidersAndDelegatesSystemLanguageDiscovery() async throws
{
  let provider = LanguageDiscoveryProbe()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let store = ModelStore(root: directory)
  #expect(throws: (any Error).self) {
    try SpeechRuntimeRegistry(store: store, providers: [provider, provider])
  }
  let registry = try SpeechRuntimeRegistry(store: store, providers: [provider])
  let catalog = try await registry.languages(for: SpeechModelDescriptor.apple.id)
  #expect(catalog.installed.map(\.id) == ["ro"])
  #expect(await provider.discoveries == 1)
}

private actor LanguageDiscoveryProbe: SpeechProvider {
  nonisolated let id = "apple"
  private(set) var discoveries = 0
  func languages(_ request: SpeechLanguageRequest) -> SpeechLanguageCatalog {
    discoveries += 1
    return SpeechLanguageCatalog(
      languages: [.init(id: "ro", name: "Romanian", isInstalled: true)], model: request.model)
  }
  func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    throw SpeechError.unavailable("Discovery must not prepare or install a model")
  }
}
