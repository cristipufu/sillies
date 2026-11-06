import Foundation
import Observation
import SilliesModelStore
import SilliesTextModels

/// Recommendations use reviewed evidence and installation state; choosing remains explicit.
@MainActor @Observable final class SetupModelSuggestions {
  struct Evidence: Codable, Sendable {
    let modelID: String
    let revision: String
    let score: Double
  }
  let text: TextModelsPresentation
  let voice: VoiceModelsPresentation
  let speech: SpeechModelsPresentation
  private(set) var evidence: [Evidence] = []
  private(set) var error: String?
  private let physicalMemory: UInt64
  private static let gibibyte: Int64 = 1_073_741_824
  private static let systemSpeechEstimate = gibibyte

  init(
    text: TextModelsPresentation, voice: VoiceModelsPresentation, speech: SpeechModelsPresentation,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) {
    self.text = text
    self.voice = voice
    self.speech = speech
    self.physicalMemory = physicalMemory
  }

  func load() async {
    guard evidence.isEmpty else { return }
    do {
      let entries = try await Task.detached(priority: .utility) {
        guard
          let url = Bundle.main.url(forResource: "SetupRecommendations", withExtension: "json")
            ?? Bundle.module.url(forResource: "SetupRecommendations", withExtension: "json")
        else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([Evidence].self, from: Data(contentsOf: url))
      }.value
      try Task.checkCancellation()
      evidence = entries.filter { $0.score.isFinite && (0...100).contains($0.score) }
    } catch is CancellationError {
    } catch {
      self.error = String(
        localized: "Model suggestions are unavailable. You can still choose any model in Settings.")
      fputs("Setup recommendation evidence: \(error)\n", stderr)
    }
  }

  func suggestedVoice(language: String) -> TTSModelManifest? {
    voice.manifests.filter {
      $0.model.supports(language: language)
        && physicalMemory / UInt64(Self.gibibyte) >= $0.model.minimumMemoryGB
    }.sorted {
      let leftInstalled = installed(voice.state(for: $0.modelID))
      let rightInstalled = installed(voice.state(for: $1.modelID))
      if leftInstalled != rightInstalled { return leftInstalled }
      return $0.downloadBytes < $1.downloadBytes
    }.first
  }

  func suggestedText(activity: SetupActivity, language: String) -> TextModelManifest? {
    let extra = auxiliaryEstimate(activity: activity, language: language)
    return text.manifests.filter {
      fits($0, additionalBytes: extra)
    }.sorted {
      let leftInstalled = installed(text.state(for: $0.modelID))
      let rightInstalled = installed(text.state(for: $1.modelID))
      if leftInstalled != rightInstalled { return leftInstalled }
      let leftScore = score(for: $0)
      let rightScore = score(for: $1)
      if leftScore != rightScore { return leftScore > rightScore }
      return $0.downloadBytes < $1.downloadBytes
    }.first
  }

  func score(for manifest: TextModelManifest) -> Double {
    evidence.first { $0.modelID == manifest.modelID && $0.revision == manifest.revision }?.score
      ?? 0
  }

  func installed(_ state: ModelInstallationState) -> Bool {
    state == .downloaded || state == .ready
  }

  private func fits(_ manifest: TextModelManifest, additionalBytes: Int64) -> Bool {
    guard physicalMemory / UInt64(Self.gibibyte) >= manifest.model.minimumMemoryGB else {
      return false
    }
    do {
      let allocation = try TextModelMemoryBudget.allocation(
        weightBytes: manifest.downloadBytes, physicalMemory: physicalMemory)
      let limit = TextModelMemoryBudget.maximumAllocation(physicalMemory: physicalMemory)
      return additionalBytes <= Int64(limit - allocation)
    } catch { return false }
  }

  private func auxiliaryEstimate(activity: SetupActivity, language: String) -> Int64 {
    guard activity == .talk || activity == .meetings else { return 0 }
    let recognition =
      speech.manifests.first { $0.modelID == speech.selectedModelID }
      .map { workspaceEstimate(bytes: $0.downloadBytes) } ?? Self.systemSpeechEstimate
    guard activity == .talk else { return recognition }
    let selected = voice.manifests.first {
      $0.modelID == voice.selectedModelID && $0.model.supports(language: language)
        && physicalMemory / UInt64(Self.gibibyte) >= $0.model.minimumMemoryGB
    }
    let synthesis =
      (selected ?? suggestedVoice(language: language))
      .map { workspaceEstimate(bytes: $0.downloadBytes) } ?? 0
    return recognition + synthesis
  }

  private func workspaceEstimate(bytes: Int64) -> Int64 {
    bytes + max(Self.gibibyte, bytes / 4)
  }
}
