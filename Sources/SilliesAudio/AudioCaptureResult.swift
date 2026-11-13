import Foundation
import SilliesCore

package struct AudioCaptureResult: Sendable {
  package var preview: String { SpeechTranscript.preview(of: transcript) }
  package let transcript: String
  package let recordingURL: URL?
  package let duration: TimeInterval
  package let failure: SessionFailure?
  package var speakerDetectionNotice: String? = nil
  package var originalTranscript: String?
  package var segments: [TranscriptSegment] = []
  package var plainText: String { segments.map(\.text).joined(separator: " ") }
  package func ending(_ reason: SessionEndReason) -> Self {
    var result = Self(
      transcript: transcript, recordingURL: recordingURL, duration: duration,
      failure: failure.flatMap { $0.requiresAttention(ending: reason) ? $0 : nil })
    result.segments = segments
    result.originalTranscript = originalTranscript
    result.speakerDetectionNotice = speakerDetectionNotice
    return result
  }
  package init(
    transcript: String, recordingURL: URL?, duration: TimeInterval, failure: SessionFailure?
  ) {
    self.transcript = transcript
    self.recordingURL = recordingURL
    self.duration = duration
    self.failure = failure
  }
}
