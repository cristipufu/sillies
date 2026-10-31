import Foundation

/// The sink applies backpressure: providers await delivery instead of building an audio backlog.
package typealias SynthesizedAudioSink = @Sendable (SynthesizedAudio) async throws -> Void

package protocol TTSProvider: Sendable {
  var id: String { get }
  func prepare(_ configuration: TTSPreparation) async throws -> any PreparedTTSModel
}

package protocol PreparedTTSModel: Sendable {
  func synthesize(_ request: SpeechSynthesisRequest, receive: SynthesizedAudioSink) async throws
  func stop() async
}

package struct TTSPreparation: Codable, Sendable, Equatable {
  package let directory: URL
  package let providerID: String
  package let variant: String
  package let resources: [TTSModelResource]
  package init(
    directory: URL, providerID: String, variant: String, resources: [TTSModelResource] = []
  ) {
    self.directory = directory
    self.providerID = providerID
    self.variant = variant
    self.resources = resources
  }
}

package struct TTSModelResource: Codable, Sendable, Equatable {
  package let path: String
  package let byteCount: Int64
  package let sha256: String
  package init(path: String, byteCount: Int64, sha256: String) {
    self.path = path
    self.byteCount = byteCount
    self.sha256 = sha256
  }
}

package struct SpeechSynthesisRequest: Codable, Sendable, Equatable {
  package static let maximumTextCharacters = 500
  package let text: String
  package let voiceID: String
  package let language: String

  package init(text: String, voiceID: String, language: String) {
    self.text = text
    self.voiceID = voiceID
    self.language = language
  }

  package func validate() throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.count <= Self.maximumTextCharacters, !voiceID.isEmpty, !language.isEmpty
    else { throw TTSError.invalidRequest }
  }
}

/// Mono float PCM. Validate external sample counts and values before touching native audio APIs.
package struct SynthesizedAudio: Codable, Sendable, Equatable {
  package static let maximumChunkSamples = 4_096
  package let samples: [Float]
  package let sampleRate: Int

  package init(samples: [Float], sampleRate: Int) throws {
    self.samples = samples
    self.sampleRate = sampleRate
    try validate()
  }

  package func validate() throws {
    guard !samples.isEmpty, samples.count <= Self.maximumChunkSamples,
      (8_000...96_000).contains(sampleRate), samples.allSatisfy({ $0.isFinite && abs($0) <= 8 })
    else { throw TTSError.invalidAudio }
  }
}
