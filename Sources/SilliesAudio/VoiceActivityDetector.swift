import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// Native WebRTC VAD only sees the echo-cleaned microphone; its state never leaves the capture worker.
final class VoiceActivityDetector {
  // -50 dBFS: AEC comfort noise can satisfy the classifier but must not open a conversation turn.
  private static let minimumSpeechPower = 0.000_01
  private let classifier: WebRTCVoiceClassifier
  private var endpoint = VoiceTurnEndpoint()
  private(set) var lastSpeechSample: TimeInterval?
  init() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    classifier = try WebRTCVoiceClassifier()
  }
  func beginNextTurn() {
    endpoint = VoiceTurnEndpoint()
    lastSpeechSample = nil
  }
  func consume(_ buffer: AVAudioPCMBuffer, endingAt time: TimeInterval) throws -> VoiceTurnEndpoint
    .Event?
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard buffer.frameLength == MeetingAudioTimeline.frameSamples,
      let samples = buffer.floatChannelData?[0]
    else { return nil }
    let detectedSpeech = try classifier.isSpeech(
      UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    let power =
      (0..<Int(buffer.frameLength)).reduce(0.0) {
        $0 + Double(samples[$1]) * Double(samples[$1])
      } / Double(buffer.frameLength)
    let isSpeech = detectedSpeech && power >= Self.minimumSpeechPower
    if isSpeech { lastSpeechSample = time }
    return endpoint.consume(
      isSpeech: isSpeech,
      duration: Double(buffer.frameLength) / buffer.format.sampleRate)
  }
}
