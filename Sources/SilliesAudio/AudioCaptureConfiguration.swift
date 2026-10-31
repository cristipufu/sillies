import Foundation
import SilliesCore
import SilliesSpeech

package struct AudioCaptureConfiguration: Sendable {
  package let kind: CompanionSkillKind
  package let target: WindowTargetCandidate?
  package let recordingURL: URL?
  package var language: SpeechLanguage?
  package var model: SpeechModelDescriptor = .apple
  package var diarizationModel: SpeechModelDescriptor?
  package var recognitionContext = SpeechRecognitionContext()
  package var dictionary = PersonalDictionary(entries: [])
  package init(
    kind: CompanionSkillKind, target: WindowTargetCandidate?, recordingURL: URL?,
    language: SpeechLanguage? = nil
  ) {
    self.kind = kind
    self.target = target
    self.recordingURL = recordingURL
    self.language = language
  }

  package var sources: [SessionAudioSource] {
    switch kind {
    case .listen, .participate: [.application, .microphone]
    case .record: [.microphone]
    default: [.application]
    }
  }
}
