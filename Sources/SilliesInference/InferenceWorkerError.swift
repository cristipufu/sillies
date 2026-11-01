import Foundation

package enum InferenceWorkerError: LocalizedError {
  case invalidMessage, interrupted, timedOut

  package var errorDescription: String? {
    switch self {
    case .invalidMessage: String(localized: "The local model returned an invalid response.")
    case .interrupted:
      String(localized: "Local model processing was interrupted. Please try again.")
    case .timedOut: String(localized: "The local model took too long. Please try a smaller model.")
    }
  }
}
