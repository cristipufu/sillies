import AVFoundation
import AudioToolbox
import Foundation
import SilliesCore
import SilliesTTS

/// Observes each actual output render quantum. AVAudioNode taps batch 100–400 ms and can
/// deliver reference audio after microphone processing, or lose a short utterance's tail.
/// The output owner stops the engine before unregistering and releasing this observer.
final class VoiceRenderReference {
  final class Delivery: Sendable {
    private static let maximumFrames = 32_768
    private static let maximumChannels: UInt32 = 32
    private let sampleRate: Double
    private let latency: TimeInterval
    private let receive: @Sendable (AudioRenderFrame) -> Void

    init(
      format: AudioStreamBasicDescription, latency: TimeInterval,
      receive: @escaping @Sendable (AudioRenderFrame) -> Void
    ) {
      sampleRate = format.mSampleRate
      self.latency = latency
      self.receive = receive
    }

    func rendered(
      _ data: UnsafeMutablePointer<AudioBufferList>?, timestamp: AudioTimeStamp,
      frames: UInt32, flags: AudioUnitRenderActionFlags
    ) {
      guard flags.contains(.unitRenderAction_PostRender),
        !flags.contains(.unitRenderAction_PostRenderError),
        timestamp.mFlags.contains(.hostTimeValid),
        frames > 0, frames <= Self.maximumFrames,
        let data, let buffer = UnsafeMutableAudioBufferListPointer(data).first,
        buffer.mNumberChannels > 0, buffer.mNumberChannels <= Self.maximumChannels,
        Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
          >= Int(frames) * Int(buffer.mNumberChannels),
        let source = buffer.mData?.assumingMemoryBound(to: Float.self)
      else { return }
      // Our player is mono. Copy its first output channel from either native interleaved
      // or planar output; resampling, AEC and VAD remain on capture's worker.
      let stride = Int(buffer.mNumberChannels)
      let samples =
        flags.contains(.unitRenderAction_OutputIsSilence)
        ? [Float](repeating: 0, count: Int(frames))
        : (0..<Int(frames)).map { source[$0 * stride] }
      receive(
        .init(
          samples: samples, sampleRate: sampleRate,
          startTime: AVAudioTime.seconds(forHostTime: timestamp.mHostTime) + latency))
    }
  }

  private let unit: AudioUnit
  private let delivery: Delivery
  private var registered = false
  private static let callback: AURenderCallback = { context, flags, timestamp, bus, frames, data in
    guard bus == 0 else { return noErr }
    Unmanaged<Delivery>.fromOpaque(context).takeUnretainedValue().rendered(
      data, timestamp: timestamp.pointee, frames: frames, flags: flags.pointee)
    return noErr
  }

  init(output: AVAudioOutputNode, receive: @escaping @Sendable (AudioRenderFrame) -> Void) throws {
    guard let unit = output.audioUnit else { throw TTSError.invalidAudio }
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard
      AudioUnitGetProperty(
        unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, &size) == noErr,
      format.mFormatID == kAudioFormatLinearPCM,
      format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      format.mBitsPerChannel == 32,
      format.mSampleRate.isFinite, format.mSampleRate > 0
    else { throw TTSError.invalidAudio }
    self.unit = unit
    delivery = Delivery(format: format, latency: output.presentationLatency, receive: receive)
    guard AudioUnitAddRenderNotify(unit, Self.callback, context) == noErr else {
      throw TTSError.invalidAudio
    }
    registered = true
  }

  func stop() {
    guard registered else { return }
    let status = AudioUnitRemoveRenderNotify(unit, Self.callback, context)
    if status != noErr {
      fputs("Playback echo reference could not unregister: \(status)\n", stderr)
    }
    registered = false
  }

  private var context: UnsafeMutableRawPointer { Unmanaged.passUnretained(delivery).toOpaque() }
}
