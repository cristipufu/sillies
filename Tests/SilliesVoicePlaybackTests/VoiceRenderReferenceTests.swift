import AVFoundation
import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesVoicePlayback

@Test(arguments: [true, false])
func playbackReferenceCopiesTheMonoVoiceFromNativeOutputLayouts(interleaved: Bool) throws {
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
  buffer.frameLength = 128
  let channels = try #require(buffer.floatChannelData)
  for index in 0..<128 {
    channels[0][index * (interleaved ? 2 : 1)] = 0.25
    channels[interleaved ? 0 : 1][index * (interleaved ? 2 : 1) + (interleaved ? 1 : 0)] = 0.5
  }
  let frames = Mutex<[AudioRenderFrame]>([])
  let delivery = VoiceRenderReference.Delivery(
    format: format.streamDescription.pointee, latency: 0.017,
    receive: { frame in frames.withLock { $0.append(frame) } })
  let timestamp = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 100)).audioTimeStamp
  delivery.rendered(
    buffer.mutableAudioBufferList, timestamp: timestamp, frames: 128,
    flags: .unitRenderAction_PostRender)
  let frame = try #require(frames.withLock { $0.first })
  #expect(frame.samples == [Float](repeating: 0.25, count: 128))
  #expect(abs(frame.startTime - 100.017) < 0.000_001)
  #expect(frame.sampleRate == 48_000)
}

@Test func playbackReferenceOnlyPublishesCompletedRendersAndHonorsNativeSilence() throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
  buffer.frameLength = 128
  try #require(buffer.floatChannelData?[0]).initialize(repeating: 0.5, count: 128)
  let frames = Mutex<[AudioRenderFrame]>([])
  let delivery = VoiceRenderReference.Delivery(
    format: format.streamDescription.pointee, latency: 0,
    receive: { frame in frames.withLock { $0.append(frame) } })
  let timestamp = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 100)).audioTimeStamp
  delivery.rendered(
    buffer.mutableAudioBufferList, timestamp: timestamp, frames: 128,
    flags: .unitRenderAction_PreRender)
  delivery.rendered(
    buffer.mutableAudioBufferList, timestamp: timestamp, frames: 128,
    flags: [.unitRenderAction_PostRender, .unitRenderAction_PostRenderError])
  delivery.rendered(
    buffer.mutableAudioBufferList, timestamp: AudioTimeStamp(), frames: 128,
    flags: .unitRenderAction_PostRender)
  #expect(frames.withLock { $0.isEmpty })
  delivery.rendered(
    buffer.mutableAudioBufferList, timestamp: timestamp, frames: 128,
    flags: [.unitRenderAction_PostRender, .unitRenderAction_OutputIsSilence])
  #expect(frames.withLock { $0.count } == 1)
  #expect(frames.withLock { $0.first?.samples } == [Float](repeating: 0, count: 128))
}

@Test func playbackReferenceRejectsIncompleteAndOversizedNativeBuffers() throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
  let delivered = Mutex(0)
  let delivery = VoiceRenderReference.Delivery(
    format: format.streamDescription.pointee, latency: 0,
    receive: { _ in delivered.withLock { $0 += 1 } })
  let timestamp = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 100)).audioTimeStamp
  var sample: Float = 0
  withUnsafeMutablePointer(to: &sample) { samples in
    var data = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 1, mDataByteSize: UInt32(MemoryLayout<Float>.size), mData: samples))
    delivery.rendered(&data, timestamp: timestamp, frames: 128, flags: .unitRenderAction_PostRender)
    delivery.rendered(
      &data, timestamp: timestamp, frames: UInt32.max, flags: .unitRenderAction_PostRender)
    data.mBuffers.mNumberChannels = UInt32.max
    delivery.rendered(&data, timestamp: timestamp, frames: 1, flags: .unitRenderAction_PostRender)
    delivery.rendered(nil, timestamp: timestamp, frames: 1, flags: .unitRenderAction_PostRender)
  }
  #expect(delivered.withLock { $0 } == 0)
}
