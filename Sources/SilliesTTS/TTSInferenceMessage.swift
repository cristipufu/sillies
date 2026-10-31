import Foundation

package struct TTSInferenceRequest: Codable, Sendable {
  package let configuration: TTSPreparation
  package let synthesis: SpeechSynthesisRequest
  package init(configuration: TTSPreparation, synthesis: SpeechSynthesisRequest) {
    self.configuration = configuration
    self.synthesis = synthesis
  }
}

package enum TTSInferenceResponse: Codable, Sendable {
  case audio(SynthesizedAudio)
  case finished
  case failure(String)
}

package enum TTSInferenceAcknowledgement: String, Codable, Sendable {
  case consumed
}
