import Foundation
import SilliesAudio
import SilliesInference
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechActivity
import SilliesSpeechWhisper

/// The optional file selects a verified research installation; normal application composition is unchanged.
enum SpeechActivityQualification {
  struct Identity: Codable {
    let modelID: String
    let revision: String
  }
  struct Configuration {
    let provider: WhisperSpeechProvider
    let identity: Identity?
  }
  private struct Manifest: Decodable, ModelArtifactManifest {
    let modelID: String
    let revision: String
    let artifacts: [ModelArtifact]
    func validate() throws { try validateArtifacts() }
  }
  private struct Request: Decodable {
    let store: String
    let manifest: Manifest
  }
  private static let maximumSpecificationBytes = 64 * 1_024

  static func configuration(specification: URL?) async throws -> Configuration {
    guard let specification else {
      return Configuration(
        provider: WhisperSpeechProvider(makeShortInputValidator: WebRTCSpeechWindowValidator.init),
        identity: nil)
    }
    let size = try specification.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard (1...maximumSpecificationBytes).contains(size) else {
      throw SpeechError.invalidAudioFormat
    }
    let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: specification))
    let store = ModelStore(root: URL(fileURLWithPath: request.store))
    let provider = WhisperSpeechProvider(
      makeShortInputValidator: WebRTCSpeechWindowValidator.init,
      prepareLongInputValidator: {
        let lease = try await store.acquire(request.manifest)
        return try await SpeechActivityModel.load(lease: lease, activity: InferenceActivity.shared)
      })
    return Configuration(
      provider: provider,
      identity: .init(modelID: request.manifest.modelID, revision: request.manifest.revision))
  }
}
