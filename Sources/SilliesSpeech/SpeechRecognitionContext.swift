import Foundation
import SilliesCore

package struct SpeechRecognitionContext: Sendable {
  package enum Purpose: Sendable { case shortUtterance, continuousTranscription }
  package var purpose: Purpose = .shortUtterance
  package enum Priority: Int, Sendable {
    case live, interactive
    package var taskPriority: TaskPriority {
      switch self {
      case .live: .utility
      case .interactive: .userInitiated
      }
    }
  }
  package var vocabulary: [String]
  package var priority: Priority
  package var boundaryMode: SpeechBoundaryPolicy.Mode?
  package func windowBoundaryMode(for configuration: SpeechWindowConfiguration)
    -> SpeechBoundaryPolicy.Mode
  {
    boundaryMode
      ?? (purpose == .continuousTranscription ? configuration.continuousBoundaryMode : .baseline)
  }
  package init(
    vocabulary: [String] = [], priority: Priority = .live,
    boundaryMode: SpeechBoundaryPolicy.Mode? = nil
  ) {
    self.vocabulary = vocabulary
    self.priority = priority
    self.boundaryMode = boundaryMode
  }
}
