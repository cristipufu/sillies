import Foundation
import SilliesCore

/// Confined by SerialQueueStorage. SDK/DSP objects never leave the capture worker.
final class AudioCaptureState {
  enum StopSource: Hashable { case microphone, application, speech }
  var lifecycle = AudioSessionLifecycle()
  var speech: SessionSpeechPipeline?
  var microphone: (any MicrophoneCapture)?
  var application: (any ApplicationCapture)?
  var writer: AudioRecordingWriter?
  var meetingAudio: MeetingAudioProcessor?
  var lastPublishedAt: TimeInterval = 0
  var pendingStops: Set<StopSource> = []
  var finishCompletions: [@Sendable (AudioCaptureResult) -> Void] = []
  var result: AudioCaptureResult?
  var finalizationOwner: AudioTranscriptionService?
  var deadline: DispatchWorkItem?
}
