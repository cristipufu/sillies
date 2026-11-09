import AVFoundation
import CoreMedia
import SilliesCore
import Testing

@testable import SilliesAudio

func audioPacketFixture(
  frames: AVAudioFrameCount = 48, channels: AVAudioChannelCount = 1,
  source: SessionAudioSource = .application
) throws
  -> AudioCaptureInputQueue.Packet
{
  let layout = try #require(
    AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels))
  let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
  buffer.frameLength = frames
  for channel in 0..<Int(channels) {
    buffer.floatChannelData?[channel].initialize(repeating: 0.2, count: Int(frames))
  }
  var description: CMAudioFormatDescription?
  #expect(
    CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, asbd: format.streamDescription,
      layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
      formatDescriptionOut: &description) == noErr)
  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero,
    decodeTimeStamp: .invalid)
  var sample: CMSampleBuffer?
  #expect(
    CMSampleBufferCreate(
      allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
      makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
      sampleCount: Int(frames),
      sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
      sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
  let ready = try #require(sample)
  #expect(
    CMSampleBufferSetDataBufferFromAudioBufferList(
      ready, blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList)
      == noErr)
  return try #require(AudioCaptureInputQueue.Packet(sample: ready, source: source))
}
