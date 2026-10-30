import Foundation
import SilliesCore

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
  var queue = DispatchQueue(label: "app.sillies.audio-session", qos: .utility)
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
  var speech: LocalSpeechFactory.Make = {
    try await LocalSpeechFactory.make(language: $0, output: $1, failure: $2)
  }
  var now: @Sendable () -> TimeInterval = { AudioCaptureClock.now }
  var finishTimeout: TimeInterval = 8
}
