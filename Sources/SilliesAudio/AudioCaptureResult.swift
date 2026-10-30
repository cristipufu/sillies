import Foundation
import SilliesCore

package struct AudioCaptureResult: Sendable {
  package var preview: String { SpeechTranscript.preview(of: transcript) }
  package let transcript: String
  package let recordingURL: URL?
  package let duration: TimeInterval
  package let failure: SessionFailure?
  package var speakerDetectionNotice: String? = nil
  package init(
    transcript: String, recordingURL: URL?, duration: TimeInterval, failure: SessionFailure?
  ) {
    self.transcript = transcript
    self.recordingURL = recordingURL
    self.duration = duration
    self.failure = failure
  }
}
