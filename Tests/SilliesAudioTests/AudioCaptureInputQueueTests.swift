import AVFoundation
import CoreMedia
import Foundation
import Synchronization
import Testing

@testable import SilliesAudio

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

private func oneMillisecondOfMeetingAudio(channels: AVAudioChannelCount = 1) throws
  -> AudioCaptureInputQueue.Packet
{
  let layout = try #require(
    AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels))
  let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48))
  buffer.frameLength = 48
  for channel in 0..<Int(channels) {
    buffer.floatChannelData?[channel].initialize(repeating: 0.2, count: 48)
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

@Test func repeatedAudioOverloadReleasesAllRetainedBuffersAndQueuedWork() async throws {
  let packet = try oneMillisecondOfMeetingAudio()
  let clock = ContinuousClock()
  let started = clock.now
  var peakBytes = 0
  for _ in 0..<20 {
    let queue = DispatchQueue(label: "sillies.test.audio-resource-cycle")
    var input: AudioCaptureInputQueue? = AudioCaptureInputQueue(queue: queue)
    weak var released = input
    let probe = AudioInputProbe()
    queue.suspend()
    for _ in 0..<5_000 {
      input?.enqueue(packet, receive: { probe.receive($0) }, overflow: { probe.overflow() })
    }
    let beforeDrain = try #require(input?.metrics)
    #expect(beforeDrain.pendingPackets <= 4_096)
    #expect(beforeDrain.retainedBytes > 0)
    #expect(beforeDrain.retainedBytes <= AudioCaptureInputQueue.maximumQueuedBytes)
    peakBytes = max(peakBytes, beforeDrain.peakRetainedBytes)
    input?.stop()
    queue.resume()
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    #expect(input?.metrics.pendingPackets == 0)
    #expect(input?.metrics.retainedBytes == 0)
    #expect(probe.overflows == 1)
    input = nil
    #expect(released == nil)
  }
  print(
    "AUDIO RESOURCE STRESS: 100000 callbacks across 20 lifecycles in \(clock.now - started); peak retained PCM bytes \(peakBytes); no pending packets after drain."
  )
}

@Test func highChannelCountAudioHitsByteLimitBeforeDurationOrCallbackLimits() async throws {
  let queue = DispatchQueue(label: "sillies.test.audio-byte-limit")
  let input = AudioCaptureInputQueue(queue: queue)
  let packet = try oneMillisecondOfMeetingAudio(channels: 64)
  let overflows = Mutex(0)
  queue.suspend()
  for _ in 0..<5_000 {
    input.enqueue(packet, receive: { _ in }, overflow: { overflows.withLock { $0 += 1 } })
  }
  let metrics = input.metrics
  queue.resume()
  await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  let bytesPerPacket = packet.sample.dataBuffer?.dataLength ?? packet.sample.totalSampleSize
  #expect(metrics.pendingPackets < 4_096)
  #expect(Double(metrics.pendingPackets) * packet.duration < 12)
  #expect(metrics.retainedBytes <= AudioCaptureInputQueue.maximumQueuedBytes)
  #expect(metrics.retainedBytes + bytesPerPacket > AudioCaptureInputQueue.maximumQueuedBytes)
  #expect(overflows.withLock { $0 } == 1)
  #expect(input.metrics.retainedBytes == 0)
  #expect(input.metrics.pendingPackets == 0)
}
