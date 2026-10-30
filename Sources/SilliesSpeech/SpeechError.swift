import Foundation

package enum SpeechError: LocalizedError {
  case unavailable(String)
  case overloaded

  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .overloaded:
      "Transcription could not keep up. Your recording continues; choose Finish & Save to preserve it."
    }
  }
}
