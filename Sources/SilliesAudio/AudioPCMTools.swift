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

/// Reuses its converter until a source format changes (for example, a microphone reconnect).
final class SpeechBufferConverter {
  private let format: AVAudioFormat
  private var converter: AVAudioConverter?
  private static let capacityPadding: Double = 16

  init(format: AVAudioFormat) { self.format = format }

  func reset() { converter?.reset() }

  func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    if input.format == format { return input }
    if converter?.inputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: format)
      converter?.primeMethod = .none
    }
    guard let converter else {
      throw AudioCaptureFailure.unavailable("Unsupported microphone format.")
    }
    let capacity = AVAudioFrameCount(
      ceil(
        Double(input.frameLength) * format.sampleRate / input.format.sampleRate
          + Self.capacityPadding))
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw AudioCaptureFailure.unavailable("Could not prepare speech audio.")
    }
    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return input
    }
    if let error { throw error }
    return output
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
