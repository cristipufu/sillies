import SilliesCore

struct ApplicationAudioRequest: Sendable {
  typealias Failure = @Sendable (SessionFailure) -> Void
  let target: WindowTargetCandidate
  let receive: AudioCaptureInputQueue.Receiver
  let failure: Failure
}
