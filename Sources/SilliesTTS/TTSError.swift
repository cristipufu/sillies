import Foundation

package enum TTSError: LocalizedError {
  case unavailable(String)
  case busy, interrupted, invalidRequest, invalidAudio, unsupportedLanguage, unsupportedVoice

  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .busy: String(localized: "A voice is already speaking. Stop it before trying another.")
    case .interrupted:
      String(localized: "Speaking was interrupted. Your reply is still available to read.")
    case .invalidRequest: String(localized: "This passage cannot be spoken. Try a shorter message.")
    case .invalidAudio:
      String(
        localized: "The voice model returned invalid audio. Your reply is still available to read.")
    case .unsupportedLanguage:
      String(
        localized:
          "This voice model doesn’t support that language. Choose another in Settings → Voices.")
    case .unsupportedVoice:
      String(localized: "That voice is unavailable for this language. Choose another voice.")
    }
  }
}
