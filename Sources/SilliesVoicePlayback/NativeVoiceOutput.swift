import AVFoundation
import Foundation
import SilliesCore
import SilliesTTS

final class NativeVoiceOutput: VoiceOutputDevice {
  private static let referenceBufferSize: AVAudioFrameCount = 512
  private static let maximumReferenceSamples = 32_768
  private let reference: (@Sendable (AudioRenderFrame) -> Void)?
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var sampleRate: Int?
  private var interrupted: (@Sendable () -> Void)?
  private var configurationObserver: (any NSObjectProtocol)?

  init(reference: (@Sendable (AudioRenderFrame) -> Void)? = nil) { self.reference = reference }
  deinit { stop() }

  func onInterruption(_ receive: @escaping @Sendable () -> Void) { interrupted = receive }

  func schedule(_ audio: SynthesizedAudio, completed: @escaping @Sendable () -> Void) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let format = try prepare(sampleRate: audio.sampleRate)
    guard let frameCount = AVAudioFrameCount(exactly: audio.samples.count),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
      let channel = buffer.floatChannelData?[0], let player
    else { throw TTSError.invalidAudio }
    buffer.frameLength = frameCount
    for (index, sample) in audio.samples.enumerated() { channel[index] = max(-1, min(1, sample)) }
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completed() }
    if !player.isPlaying { player.play() }
  }

  func stop() {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    player?.stop()
    if reference != nil { engine?.mainMixerNode.removeTap(onBus: 0) }
    engine?.stop()
    player = nil
    engine = nil
    sampleRate = nil
  }

  private func prepare(sampleRate requestedRate: Int) throws -> AVAudioFormat {
    guard
      let format = AVAudioFormat(standardFormatWithSampleRate: Double(requestedRate), channels: 1)
    else { throw TTSError.invalidAudio }
    if engine != nil {
      guard sampleRate == requestedRate else { throw TTSError.invalidAudio }
      return format
    }
    let engine = AVAudioEngine()
    let output = engine.outputNode.outputFormat(forBus: 0)
    guard output.sampleRate > 0, output.channelCount > 0 else {
      throw TTSError.unavailable(
        String(localized: "No audio output is available. Your reply is still available as text."))
    }
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    installReferenceTap(on: engine)
    engine.prepare()
    try engine.start()
    if let interrupted {
      configurationObserver = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
      ) { _ in interrupted() }
    }
    self.engine = engine
    self.player = player
    sampleRate = requestedRate
    return format
  }

  private func installReferenceTap(on engine: AVAudioEngine) {
    guard let reference else { return }
    let latency = engine.outputNode.presentationLatency
    engine.mainMixerNode.installTap(
      onBus: 0, bufferSize: Self.referenceBufferSize, format: nil
    ) { buffer, time in
      guard time.isHostTimeValid, buffer.frameLength > 0,
        buffer.frameLength <= Self.maximumReferenceSamples,
        let samples = buffer.floatChannelData?[0]
      else { return }
      reference(
        .init(
          samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))),
          sampleRate: buffer.format.sampleRate,
          startTime: AVAudioTime.seconds(forHostTime: time.hostTime) + latency))
    }
  }
}
