import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// AVAudioConverter may retain part of an input buffer and return it in a later call.
/// Timestamp produced samples by their position in the stream, not the newest callback.
final class MeetingAudioResampler {
  struct Output {
    let buffer: AVAudioPCMBuffer
    let startTime: TimeInterval
  }
  private let converter: SpeechBufferConverter
  private let outputRate: Double
  private var inputFormat: AVAudioFormat?
  private var expectedInputTime: TimeInterval?
  private var bufferedDuration: TimeInterval = 0
  private(set) var outputEndTime: TimeInterval?

  init(format: AVAudioFormat) {
    converter = SpeechBufferConverter(format: format)
    outputRate = format.sampleRate
  }

  func convert(_ input: AVAudioPCMBuffer, at time: TimeInterval) throws -> Output {
    guard time.isFinite, time >= 0 else { throw MeetingAudioTimeline.Failure.invalidTime }
    let sampleTolerance = 1 / min(input.format.sampleRate, outputRate)
    if inputFormat != input.format
      || expectedInputTime.map({ abs(time - $0) > sampleTolerance }) == true
    {
      reset()
    }
    let buffer = try converter.convert(input)
    let start = max(0, time - bufferedDuration)
    let inputDuration = Double(input.frameLength) / input.format.sampleRate
    let outputDuration = Double(buffer.frameLength) / outputRate
    bufferedDuration += inputDuration - outputDuration
    expectedInputTime = time + inputDuration
    inputFormat = input.format
    outputEndTime = start + outputDuration
    return Output(buffer: buffer, startTime: start)
  }

  func reset() {
    converter.reset()
    inputFormat = nil
    expectedInputTime = nil
    bufferedDuration = 0
    outputEndTime = nil
  }
}
