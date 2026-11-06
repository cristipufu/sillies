import AVFoundation
import SilliesCore

package enum MicrophoneAuthorization {
  /// Undecided authorization is requested only by the user's explicit capture action.
  package static func failure() -> SessionFailure? {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .denied, .restricted: .permissionDenied(.openMicrophoneSettings)
    default: nil
    }
  }
}
