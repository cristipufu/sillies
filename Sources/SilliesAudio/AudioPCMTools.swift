import AVFoundation
import CoreMedia

/// Buffer work stays on the capture worker, never the UI or the microphone's real-time thread.
enum AudioPCMTools {
  private static let rmsSampleBudget = 128
  private static let rmsGain = 6.0

  static func buffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let description = sample.formatDescription, sample.numSamples > 0 else { return nil }
    let format = AVAudioFormat(cmAudioFormatDescription: description)
    let count = AVAudioFrameCount(sample.numSamples)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
    buffer.frameLength = count
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sample, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
    return status == noErr ? buffer : nil
  }

  static func level(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    let count = Int(buffer.frameLength)
    let step = max(1, count / rmsSampleBudget)
    var squares: Float = 0
    var sampled = 0
    for index in stride(from: 0, to: count, by: step) {
      squares += samples[index] * samples[index]
      sampled += 1
    }
    return min(1, Double(sqrt(squares / Float(sampled))) * rmsGain)
  }
}

enum AudioCaptureFailure: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    }
  }
}
