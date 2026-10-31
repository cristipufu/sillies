import Foundation

package enum InferenceWorkerError: LocalizedError {
  case invalidMessage, interrupted, timedOut

  package var errorDescription: String? {
    switch self {
    case .invalidMessage: "The local model returned an invalid response."
    case .interrupted: "Local model processing was interrupted. Please try again."
    case .timedOut: "The local model took too long. Please try a smaller model."
    }
  }
}
