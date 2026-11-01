import AVFoundation
import Foundation
import Testing

@testable import SilliesAudio

@Test(arguments: [8_000.0, 16_000, 22_050, 24_000, 44_100, 48_000, 96_000])
func meetingResamplingKeepsSamplesContiguousAcrossVariableInputBlocks(rate: Double) throws {
  let outputRate = 16_000.0
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1))
  let converter = MeetingAudioResampler(format: format)
  var inputFrames = 0
  var outputFrames = 0
  for size in Array(repeating: [128, 512, 4_800, 1_024], count: 8).flatMap({ $0 }) {
    let output = try converter.convert(
      resamplingBuffer(rate: rate, count: size), at: 100 + Double(inputFrames) / rate)
    #expect(abs(output.startTime - (100 + Double(outputFrames) / outputRate)) < 1 / outputRate)
    inputFrames += size
    outputFrames += Int(output.buffer.frameLength)
    #expect(
      abs(try #require(converter.outputEndTime) - (100 + Double(outputFrames) / outputRate)) < 1
        / outputRate)
  }
}

@Test func meetingResamplingStartsANewSegmentAfterGapsAndFormatChanges() throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let converter = MeetingAudioResampler(format: format)
  _ = try converter.convert(resamplingBuffer(rate: 48_000, count: 4_800), at: 100)
  let afterGap = try converter.convert(resamplingBuffer(rate: 48_000, count: 512), at: 101)
  #expect(afterGap.startTime == 101)
  let afterFormatChange = try converter.convert(
    resamplingBuffer(rate: 44_100, count: 512), at: 101 + 512.0 / 48_000)
  #expect(afterFormatChange.startTime == 101 + 512.0 / 48_000)
  converter.reset()
  #expect(converter.outputEndTime == nil)
  #expect(
    try converter.convert(resamplingBuffer(rate: 48_000, count: 512), at: 200).startTime == 200)
}

private func resamplingBuffer(rate: Double, count: Int) throws -> AVAudioPCMBuffer {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
  let count = try #require(AVAudioFrameCount(exactly: count))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
  buffer.frameLength = count
  let samples = try #require(buffer.floatChannelData?[0])
  samples.initialize(repeating: 0, count: Int(count))
  return buffer
}
