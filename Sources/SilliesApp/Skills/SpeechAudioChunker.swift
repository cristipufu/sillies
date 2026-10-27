import AVFoundation

/// Normalizes variable capture callbacks into a bounded amount of audio per speech request.
/// Owned by the speech channel and used only on its input queue.
final class SpeechAudioChunker {
  static let chunkDuration: TimeInterval = 0.1
  static let bufferedDuration: TimeInterval = 12
  static let streamCapacity = Int(bufferedDuration / chunkDuration)
  private let format: AVAudioFormat
  private let chunkFrames: AVAudioFrameCount
  private var pending: AVAudioPCMBuffer?

  init(format: AVAudioFormat) {
    self.format = format
    chunkFrames = AVAudioFrameCount(max(1, format.sampleRate * Self.chunkDuration))
  }

  func append(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
    guard input.format == format else {
      throw AudioCaptureFailure.unavailable("Speech audio changed to an unexpected format.")
    }
    var chunks: [AVAudioPCMBuffer] = []
    var offset: AVAudioFrameCount = 0
    while offset < input.frameLength {
      if pending == nil {
        pending = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
      }
      guard let pending else {
        throw AudioCaptureFailure.unavailable("Could not prepare speech audio.")
      }
      let count = min(chunkFrames - pending.frameLength, input.frameLength - offset)
      try copy(input, offset: offset, count: count, into: pending)
      pending.frameLength += count
      offset += count
      if pending.frameLength == chunkFrames {
        chunks.append(pending)
        self.pending = nil
      }
    }
    return chunks
  }

  func flush() -> AVAudioPCMBuffer? {
    defer { pending = nil }
    return pending
  }

  private func copy(
    _ input: AVAudioPCMBuffer, offset: AVAudioFrameCount,
    count: AVAudioFrameCount, into output: AVAudioPCMBuffer
  ) throws {
    let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
    let source = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
    let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
    for (sourceBuffer, destinationBuffer) in zip(source, destination) {
      guard let from = sourceBuffer.mData, let to = destinationBuffer.mData else {
        throw AudioCaptureFailure.unavailable("Speech audio contained an empty channel.")
      }
      memcpy(
        to.advanced(by: Int(output.frameLength) * bytesPerFrame),
        from.advanced(by: Int(offset) * bytesPerFrame), Int(count) * bytesPerFrame)
    }
  }
}
