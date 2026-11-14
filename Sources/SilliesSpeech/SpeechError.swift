import Foundation

package enum SpeechError: LocalizedError {
  case unavailable(String)
  case overloaded

  package static var invalidAudioFormat: SpeechError {
    .unavailable(String(localized: "Speech audio changed to an unexpected format."))
  }

  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .overloaded:
      String(
        localized:
          "Transcription could not keep up. Your recording continues; choose Finish & Save to preserve it."
      )
    }
  }
}
