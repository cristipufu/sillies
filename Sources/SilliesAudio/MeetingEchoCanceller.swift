import CEchoCancellation
import Foundation
import SilliesCore

/// Owns the local WebRTC AEC3 state. Confined to the session's audio worker; never opens a device.
final class MeetingEchoCanceller {
  private let state: OpaquePointer

  init() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let state = sillies_echo_create() else {
      throw AudioCaptureFailure.unavailable("Could not prepare speaker echo cancellation.")
    }
    self.state = state
  }

  deinit { sillies_echo_destroy(state) }

  func reset() throws {
    try check(sillies_echo_reset(state))
  }

  func process(reference: [Float], microphone: [Float]) throws -> [Float] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard reference.count == MeetingAudioTimeline.frameSamples,
      microphone.count == MeetingAudioTimeline.frameSamples
    else {
      throw AudioCaptureFailure.unavailable("Unexpected echo-cancellation audio frame size.")
    }
    var output = [Float](repeating: 0, count: MeetingAudioTimeline.frameSamples)
    let status = reference.withUnsafeBufferPointer { reference in
      microphone.withUnsafeBufferPointer { microphone in
        output.withUnsafeMutableBufferPointer { output in
          sillies_echo_process(
            state, reference.baseAddress, microphone.baseAddress, output.baseAddress)
        }
      }
    }
    try check(status)
    return output
  }

  private func check(_ status: Int32) throws {
    guard status == 0 else {
      throw AudioCaptureFailure.unavailable(
        "Speaker echo processing stopped (\(status)). Finish to save this session.")
    }
  }
}
