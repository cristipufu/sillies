/// Determines how a bounded recognition window commits its words and retires its audio.
package enum SpeechWindowCompletion: String, Codable, Sendable {
  case draft, boundary, utterance, session

  var inferencePhase: SpeechWindowPosition.Phase {
    switch self {
    case .draft: .partial
    case .boundary: .boundary
    case .utterance, .session: .complete
    }
  }
}
