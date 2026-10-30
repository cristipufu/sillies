import Foundation
import SilliesCore

package struct AudioCaptureConfiguration: Sendable {
  package let kind: CompanionSkillKind
  package let target: WindowTargetCandidate?
  package let recordingURL: URL?
  package var language: SpeechLanguage?
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
