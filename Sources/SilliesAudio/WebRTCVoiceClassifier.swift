import CEchoCancellation
import Foundation
import SilliesCore
import SilliesSpeech

/// Owns one native classifier; callers never share its adaptive history across sources or replays.
final class WebRTCVoiceClassifier {
  enum Mode { case conversation, transcription }
  static let frameSamples = MeetingAudioTimeline.frameSamples
  private let handle: OpaquePointer
  init(mode: Mode = .conversation) throws {
    let nativeMode =
      mode == .conversation ? SilliesVoiceActivityConversation : SilliesVoiceActivityTranscription
    guard let handle = sillies_vad_create(nativeMode) else {
      throw SpeechError.unavailable(String(localized: "Could not prepare voice detection."))
    }
    self.handle = handle
  }
  deinit { sillies_vad_destroy(handle) }

  func isSpeech(_ samples: [Float]) throws -> Bool {
    try samples.withUnsafeBufferPointer { try isSpeech($0) }
  }

  func isSpeech(_ samples: UnsafeBufferPointer<Float>) throws -> Bool {
    guard !samples.isEmpty, samples.count <= Self.frameSamples else {
      throw SpeechError.invalidAudioFormat
    }
    if samples.count == Self.frameSamples { return try classify(samples) }
    var frame = [Float](repeating: 0, count: Self.frameSamples)
    frame.replaceSubrange(0..<samples.count, with: samples)
    return try frame.withUnsafeBufferPointer { try classify($0) }
  }

  private func classify(_ samples: UnsafeBufferPointer<Float>) throws -> Bool {
    let result = sillies_vad_process(handle, samples.baseAddress, samples.count)
    guard result >= 0 else {
      throw SpeechError.unavailable(
        String(localized: "Voice detection could not process the microphone."))
    }
    return result == 1
  }
}
