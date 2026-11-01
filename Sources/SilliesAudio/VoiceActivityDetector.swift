import AVFoundation
import CEchoCancellation
import Foundation
import SilliesCore

/// Native WebRTC VAD only sees the echo-cleaned microphone; its state never leaves the capture worker.
final class VoiceActivityDetector {
  // -50 dBFS: AEC comfort noise can satisfy the classifier but must not open a conversation turn.
  private static let minimumSpeechPower = 0.000_01
  private let state: OpaquePointer
  private var endpoint = VoiceTurnEndpoint()
  init() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let state = sillies_vad_create() else {
      throw AudioCaptureFailure.unavailable(String(localized: "Could not prepare voice detection."))
    }
    self.state = state
  }
  deinit { sillies_vad_destroy(state) }
  func beginNextTurn() { endpoint = VoiceTurnEndpoint() }
  func consume(_ buffer: AVAudioPCMBuffer) throws -> VoiceTurnEndpoint.Event? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard buffer.frameLength == MeetingAudioTimeline.frameSamples,
      let samples = buffer.floatChannelData?[0]
    else { return nil }
    let result = sillies_vad_process(state, samples, Int(buffer.frameLength))
    guard result >= 0 else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "Voice detection could not process the microphone."))
    }
    let power =
      (0..<Int(buffer.frameLength)).reduce(0.0) {
        $0 + Double(samples[$1]) * Double(samples[$1])
      } / Double(buffer.frameLength)
    return endpoint.consume(
      isSpeech: result == 1 && power >= Self.minimumSpeechPower,
      duration: Double(buffer.frameLength) / buffer.format.sampleRate)
  }
}
