import Foundation

package struct AudioCaptureResult: Sendable {
  package var preview: String { SpeechTranscript.preview(of: transcript) }
  package let transcript: String
  package let recordingURL: URL?
  package let duration: TimeInterval
  package let error: String?
  package init(transcript: String, recordingURL: URL?, duration: TimeInterval, error: String?) {
    self.transcript = transcript
    self.recordingURL = recordingURL
    self.duration = duration
    self.error = error
  }
}
