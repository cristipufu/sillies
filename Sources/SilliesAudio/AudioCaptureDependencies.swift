import Foundation
import SilliesCore
import SilliesSpeech

protocol MicrophoneCapture: AnyObject, Sendable {
  func start() async throws -> String
  func stop(completion: @escaping @Sendable () -> Void)
}
protocol ApplicationCapture: AnyObject, Sendable {
  func start() async throws
  func stop(completion: @escaping @Sendable () -> Void)
}
extension MicrophoneAudioSource: MicrophoneCapture {}
extension ApplicationAudioSource: ApplicationCapture {}

/// Device factories and a clock let lifecycle tests reorder callbacks without hardware or sleeps.
struct AudioCaptureDependencies: Sendable {
  // Processing live input has the same priority as its device callbacks, even during background inference.
  var queue = DispatchQueue(label: "app.sillies.audio-session", qos: .userInitiated)
  var reportOverload: @Sendable (AudioCaptureBacklog) -> Void = { _ in }
  var lifecycle: @Sendable (AudioCaptureLifecycleEvent) -> Void = { _ in }
  typealias Failure = @Sendable (SessionFailure) -> Void
  var microphone:
    @Sendable (@escaping AudioCaptureInputQueue.Receiver, @escaping Failure) ->
      any MicrophoneCapture = {
        MicrophoneAudioSource(receive: $0, failure: $1)
      }
  var application:
    @Sendable (WindowTargetCandidate, @escaping AudioCaptureInputQueue.Receiver, @escaping Failure)
      -> any ApplicationCapture = {
        ApplicationAudioSource(target: $0, receive: $1, failure: $2)
      }
  var speech: LocalSpeechFactory.Make
  var diarization: SpeakerDiarizationFactory.Make?
  var now: @Sendable () -> TimeInterval = { AudioCaptureClock.now }
  var finishTimeout: TimeInterval = 8
  var meetingFinishTimeout: TimeInterval = 30

  func finalizationTimeout(for kind: CompanionSkillKind) -> TimeInterval {
    // Meeting sources can each have an unfinished window. Device stops begin immediately;
    // one budget includes final text, speaker labels and completion delivery.
    kind.isMeetingSession ? meetingFinishTimeout : finishTimeout
  }
}
