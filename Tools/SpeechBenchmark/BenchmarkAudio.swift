import AVFoundation
import Foundation
import SilliesSpeech

enum BenchmarkAudio {
  struct Timing {
    let duration: TimeInterval
    let finalization: Duration
  }
  private static let packetDuration = 0.1
  private static let maximumDuration = 30.0

  @concurrent static func feed(_ url: URL, to channels: [any LocalSpeechChannel]) async throws
    -> Timing
  {
    let file = try AVAudioFile(forReading: url)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    guard duration <= maximumDuration else {
      throw SpeechError.unavailable("Benchmark fixtures must be at most 30 seconds.")
    }
    while file.framePosition < file.length {
      try Task.checkCancellation()
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat,
          frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * packetDuration))
      else {
        throw SpeechError.unavailable("Could not allocate fixture buffer.")
      }
      try file.read(into: buffer)
      for channel in channels { channel.append(buffer) }
      try await Task.sleep(for: .seconds(Double(buffer.frameLength) / buffer.format.sampleRate))
    }
    let releasedAt = ContinuousClock.now
    for channel in channels {
      await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    }
    return Timing(duration: duration, finalization: releasedAt.duration(to: .now))
  }
}
