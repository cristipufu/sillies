import Foundation
import SilliesTTS

/// Marks the boundary after registry admission and installation verification, before helper launch.
actor VoiceProfileProvider: TTSProvider {
  nonisolated let id: String
  private let provider: any TTSProvider
  private(set) var preparationStartedAt: TimeInterval?

  init(_ provider: any TTSProvider) {
    self.provider = provider
    id = provider.id
  }

  func prepare(_ configuration: TTSPreparation) async throws -> any PreparedTTSModel {
    preparationStartedAt = ProcessInfo.processInfo.systemUptime
    return try await provider.prepare(configuration)
  }
}
