import CoreAudio
import CoreMedia
import Foundation
import Synchronization

/// Copies one bounded mono Float32 stream. Borrowed HAL pointers never cross the callback boundary.
final class CoreAudioPacketEmitter: Sendable {
  static let maximumFrames = 65_536
  static let minimumSampleRate = 8_000.0
  static let maximumSampleRate = 384_000.0
  private static let bytesPerSample = UInt32(MemoryLayout<Float>.size)
  private static let bitsPerSample: UInt32 = 32
  private static let channelCount: UInt32 = 1
  private static let frameDurationTimescale: Int32 = 1_000_000_000
  private enum Phase {
    case receiving
    case suspended(UUID)
    case stopped
  }
  private let phase = Mutex(Phase.receiving)
  private let format: CMAudioFormatDescription
  private let sampleRate: Double
  private let receivePacket: AudioCaptureInputQueue.Receiver
  private let failure: @Sendable (CoreAudioCaptureError) -> Void

  init(
    format: AudioStreamBasicDescription, receive: @escaping AudioCaptureInputQueue.Receiver,
    failure: @escaping @Sendable (CoreAudioCaptureError) -> Void
  ) throws {
    guard Self.supports(format) else { throw CoreAudioCaptureError.unsupported }
    var value = format
    var description: CMAudioFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, asbd: &value,
      layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
      formatDescriptionOut: &description)
    guard status == noErr, let description else {
      throw CoreAudioCaptureError.native(.copyPacket, status == noErr ? kAudio_ParamError : status)
    }
    self.format = description
    sampleRate = format.mSampleRate
    receivePacket = receive
    self.failure = failure
  }
  static func supports(_ format: AudioStreamBasicDescription) -> Bool {
    format.mFormatID == kAudioFormatLinearPCM
      && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
      && format.mFormatFlags & kAudioFormatFlagIsPacked != 0
      && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
      && format.mSampleRate.isFinite
      && (minimumSampleRate...maximumSampleRate).contains(format.mSampleRate)
      && format.mChannelsPerFrame == channelCount && format.mBitsPerChannel == bitsPerSample
      && format.mFramesPerPacket == 1 && format.mBytesPerFrame == bytesPerSample
      && format.mBytesPerPacket == bytesPerSample
  }
  func receive(_ input: UnsafePointer<AudioBufferList>, at timestamp: AudioTimeStamp) {
    autoreleasepool { receiveOwnedCopy(input, at: timestamp) }
  }
  private func receiveOwnedCopy(
    _ input: UnsafePointer<AudioBufferList>, at timestamp: AudioTimeStamp
  ) {
    let result: Result<AudioCaptureInputQueue.Packet?, CoreAudioCaptureError> = phase.withLock {
      phase in
      guard case .receiving = phase else { return .success(nil) }
      do { return .success(try copy(input, at: timestamp)) } catch {
        phase = .stopped
        return .failure(
          (error as? CoreAudioCaptureError) ?? .native(.copyPacket, kAudio_ParamError))
      }
    }
    switch result {
    case .success(let packet): if let packet { receivePacket(packet) }
    case .failure(let error): failure(error)
    }
  }
  private func copy(_ input: UnsafePointer<AudioBufferList>, at timestamp: AudioTimeStamp) throws
    -> AudioCaptureInputQueue.Packet?
  {
    guard input.pointee.mNumberBuffers == 1 else { throw CoreAudioCaptureError.unsupported }
    let buffer = input.pointee.mBuffers
    if buffer.mDataByteSize == 0 { return nil }
    guard buffer.mNumberChannels == Self.channelCount, buffer.mData != nil,
      buffer.mDataByteSize % Self.bytesPerSample == 0,
      buffer.mDataByteSize / Self.bytesPerSample <= Self.maximumFrames
    else { throw CoreAudioCaptureError.unsupported }
    let frames = Int(buffer.mDataByteSize / Self.bytesPerSample)
    let duration = Double(frames) / sampleRate
    var sample: CMSampleBuffer?
    var status = CMAudioSampleBufferCreateWithPacketDescriptions(
      allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
      makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: frames,
      presentationTimeStamp: presentationTime(timestamp, duration: duration),
      packetDescriptions: nil, sampleBufferOut: &sample)
    guard status == noErr, let sample else {
      throw CoreAudioCaptureError.native(.copyPacket, status == noErr ? kAudio_ParamError : status)
    }
    status = CMSampleBufferSetDataBufferFromAudioBufferList(
      sample, blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: input)
    guard status == noErr else { throw CoreAudioCaptureError.native(.copyPacket, status) }
    status = CMSampleBufferSetDataReady(sample)
    guard status == noErr,
      let packet = AudioCaptureInputQueue.Packet(sample: sample, source: .application)
    else {
      throw CoreAudioCaptureError.native(.copyPacket, status == noErr ? kAudio_ParamError : status)
    }
    return packet
  }
  private func presentationTime(_ timestamp: AudioTimeStamp, duration: TimeInterval) -> CMTime {
    if timestamp.mFlags.contains(.hostTimeValid), timestamp.mHostTime > 0,
      timestamp.mHostTime <= UInt64(Int64.max)
    {
      let time = CMClockMakeHostTimeFromSystemUnits(timestamp.mHostTime)
      if time.seconds.isFinite, time.seconds > 0 { return time }
    }
    return CMTime(
      seconds: AudioCaptureClock.now - duration, preferredTimescale: Self.frameDurationTimescale)
  }
  func suspend() -> UUID? {
    phase.withLock {
      if case .stopped = $0 { return nil }
      let ticket = UUID()
      $0 = .suspended(ticket)
      return ticket
    }
  }
  func resume(_ ticket: UUID) {
    phase.withLock { if case .suspended(let current) = $0, current == ticket { $0 = .receiving } }
  }
  func stop() { phase.withLock { $0 = .stopped } }
}
