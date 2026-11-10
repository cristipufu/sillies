import Foundation
import SilliesCore

/// Confined by SerialQueueStorage. SDK/DSP objects never leave the capture worker.
final class AudioCaptureState {
  typealias StopSource = AudioCaptureLifecycleEvent.Resource
  var lifecycle = AudioSessionLifecycle()
  var speech: SessionSpeechPipeline?
  var transcriptionFailure: SessionFailure?
  var speakerDetectionNotice: String?
  var microphone: (any MicrophoneCapture)?
  var application: (any ApplicationCapture)?
  var writer: AudioRecordingWriter?
  var meetingAudio: MeetingAudioProcessor?
  var lastPublishedAt: TimeInterval = 0
  var pendingStops: Set<StopSource> = []
  var requestedStops: Set<StopSource> = []
  var finishCompletions: [@Sendable (AudioCaptureResult) -> Void] = []
  var result: AudioCaptureResult?
  var finalizationOwner: AudioTranscriptionService?
  var deadline: DispatchWorkItem?
}
