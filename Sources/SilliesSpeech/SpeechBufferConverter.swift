import AVFoundation

/// Reuses its converter until a source format changes (for example, a microphone reconnect).
package final class SpeechBufferConverter {
  private let format: AVAudioFormat
  private var converter: AVAudioConverter?
  private static let capacityPadding: Double = 16

  package init(format: AVAudioFormat) { self.format = format }

  package func reset() { converter?.reset() }

  package func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    if input.format == format { return input }
    if converter?.inputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: format)
      converter?.primeMethod = .none
    }
    guard let converter else {
      throw SpeechError.unavailable("Unsupported microphone format.")
    }
    let capacity = AVAudioFrameCount(
      ceil(
        Double(input.frameLength) * format.sampleRate / input.format.sampleRate
          + Self.capacityPadding))
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw SpeechError.unavailable("Could not prepare speech audio.")
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
