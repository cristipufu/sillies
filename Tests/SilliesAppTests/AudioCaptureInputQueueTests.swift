import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import SilliesApp

@Test func captureQueueDrainsRapidMeetingCallbacksWithoutDroppingSamples() async throws {
  let queue = DispatchQueue(label: "sillies.test.rapid-audio")
  let input = AudioCaptureInputQueue(queue: queue)
  let packet = try oneMillisecondOfMeetingAudio()
  let probe = AudioInputProbe()
  queue.suspend()
  for _ in 0..<2_000 {
    input.enqueue(packet, receive: { probe.receive($0) }, overflow: { probe.overflow() })
  }
  input.stop()
  input.enqueue(packet, receive: { probe.receive($0) }, overflow: { probe.overflow() })
  queue.resume()
  await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  #expect(probe.frames == 96_000)
  #expect(probe.overflows == 0)
}

@Test func captureQueueReportsSustainedOverloadOnceAndRemainsBounded() async throws {
  let queue = DispatchQueue(label: "sillies.test.overloaded-audio")
  let input = AudioCaptureInputQueue(queue: queue)
  let packet = try oneMillisecondOfMeetingAudio()
  let probe = AudioInputProbe()
  queue.suspend()
  for _ in 0..<5_000 {
    input.enqueue(packet, receive: { probe.receive($0) }, overflow: { probe.overflow() })
  }
  queue.resume()
  await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  #expect(probe.overflows == 1)
  #expect(probe.frames > 0 && probe.frames < 5_000 * 48)
}

private func oneMillisecondOfMeetingAudio() throws -> AudioCaptureInputQueue.Packet {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48))
  buffer.frameLength = 48
  buffer.floatChannelData?[0].initialize(repeating: 0.2, count: 48)
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
      makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: 48,
      sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
      sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
  let ready = try #require(sample)
  #expect(
    CMSampleBufferSetDataBufferFromAudioBufferList(
      ready, blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList)
      == noErr)
  return try #require(AudioCaptureInputQueue.Packet(sample: ready, source: .application))
}

private final class AudioInputProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var receivedFrames = 0
  private var overflowCount = 0
  var frames: Int { lock.withLock { receivedFrames } }
  var overflows: Int { lock.withLock { overflowCount } }
  func receive(_ packet: AudioCaptureInputQueue.Packet) {
    let frames = AudioPCMTools.buffer(from: packet.sample)?.frameLength ?? 0
    lock.withLock { receivedFrames += Int(frames) }
  }
  func overflow() { lock.withLock { overflowCount += 1 } }
}
