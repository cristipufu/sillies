import CoreAudio
import CoreMedia
import Foundation
import Synchronization
import Testing

@testable import SilliesAudio

@Test(arguments: [8_000.0, 44_100, 44_100.125, 48_000, 96_000, 384_000])
func coreAudioPacketsOwnCopiedSamplesAndPreserveDeviceClock(_ rate: Double) throws {
  let packets = Mutex<[AudioCaptureInputQueue.Packet]>([])
  var format = CoreAudioTestSystem.format
  format.mSampleRate = rate
  let emitter = try CoreAudioPacketEmitter(
    format: format,
    receive: { packet in
      packets.withLock { $0.append(packet) }
    }, failure: { _ in Issue.record("Unexpected packet failure") })
  let host = CMClockConvertHostTimeToSystemUnits(
    CMTime(seconds: 100, preferredTimescale: 1_000_000))
  var timestamp = AudioTimeStamp()
  timestamp.mFlags = .hostTimeValid
  timestamp.mHostTime = host
  let capturedTimestamp = timestamp
  coreAudioSend({ input, _ in emitter.receive(input, at: capturedTimestamp) })
  let packet = try #require(packets.withLock { $0.first })
  #expect(packet.source == .application)
  #expect(abs(packet.sampleStartTime - 100) < 0.000_001)
  #expect(abs(packet.duration - 2 / rate) < 0.000_001)
  var copied = [Float](repeating: 0, count: 2)
  let block = try #require(packet.sample.dataBuffer)
  let status = try copied.withUnsafeMutableBytes {
    CMBlockBufferCopyDataBytes(
      block, atOffset: 0, dataLength: $0.count, destination: try #require($0.baseAddress))
  }
  #expect(status == noErr)
  #expect(copied == [0.25, -0.5])
}

private enum InvalidPacket: CaseIterable, Sendable {
  case buffers, channels, nilData, unaligned, oversized
}
@Test(arguments: InvalidPacket.allCases)
private func coreAudioMalformedPacketsFailOnceBeforeReadingMemory(_ input: InvalidPacket) throws {
  let failures = Mutex(0)
  let emitter = try CoreAudioPacketEmitter(
    format: CoreAudioTestSystem.format,
    receive: { _ in Issue.record("Malformed input was accepted") },
    failure: { _ in failures.withLock { $0 += 1 } })
  var sample: Float = 0.5
  withUnsafeMutablePointer(to: &sample) { pointer in
    var list = AudioBufferList(
      mNumberBuffers: input == .buffers ? .max : 1,
      mBuffers: AudioBuffer(
        mNumberChannels: input == .channels ? 2 : 1,
        mDataByteSize: input == .unaligned ? 3 : input == .oversized ? .max - 3 : 4,
        mData: input == .nilData ? nil : pointer))
    withUnsafePointer(to: &list) {
      emitter.receive($0, at: .init())
      emitter.receive($0, at: .init())
    }
  }
  #expect(failures.withLock { $0 } == 1)
}

@Test func coreAudioSuspensionTicketsRejectStaleResumptionAndStopIsTerminal() throws {
  let packets = Mutex(0)
  let emitter = try CoreAudioPacketEmitter(
    format: CoreAudioTestSystem.format,
    receive: { _ in packets.withLock { $0 += 1 } },
    failure: { _ in Issue.record("Unexpected error") })
  let first = try #require(emitter.suspend())
  let second = try #require(emitter.suspend())
  emitter.resume(first)
  coreAudioSend(emitter.receive)
  #expect(packets.withLock { $0 } == 0)
  emitter.resume(second)
  coreAudioSend(emitter.receive, values: [0, 0])
  #expect(packets.withLock { $0 } == 1)  // Silence remains valid audio, never a fallback signal.
  emitter.stop()
  emitter.resume(second)
  coreAudioSend(emitter.receive)
  #expect(packets.withLock { $0 } == 1)
  #expect(emitter.suspend() == nil)
}

@Test func coreAudioRejectsUnsafeNativeFormats() {
  for rate in [Double.nan, .infinity, -.infinity, 0, 7_999, 384_001] {
    var format = CoreAudioTestSystem.format
    format.mSampleRate = rate
    #expect(!CoreAudioPacketEmitter.supports(format))
  }
  var format = CoreAudioTestSystem.format
  format.mChannelsPerFrame = 2
  #expect(!CoreAudioPacketEmitter.supports(format))
  format = CoreAudioTestSystem.format
  format.mBytesPerFrame = .max
  #expect(!CoreAudioPacketEmitter.supports(format))
  format = CoreAudioTestSystem.format
  format.mFormatFlags = kAudioFormatFlagIsSignedInteger
  #expect(!CoreAudioPacketEmitter.supports(format))
}
