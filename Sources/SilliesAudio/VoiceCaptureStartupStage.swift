import Foundation
import SilliesCore

/// The visible stage and recovery category describe the resource actually being prepared.
enum VoiceCaptureStartupStage {
  case speech, microphone

  var status: String {
    switch self {
    case .speech: String(localized: "Preparing speech…")
    case .microphone: String(localized: "Getting the microphone ready…")
    }
  }

  var timeoutFailure: SessionFailure {
    switch self {
    case .speech:
      .init(
        category: .transcription,
        message: String(
          localized: "Speech recognition took too long to get ready. Please try speaking again."))
    case .microphone:
      .init(
        category: .captureUnavailable,
        message: String(
          localized: "The microphone could not start. Check that it is connected."))
    }
  }
}
