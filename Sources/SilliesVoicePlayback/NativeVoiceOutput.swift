import AVFoundation
import Foundation
import SilliesTTS

final class NativeVoiceOutput: VoiceOutputDevice {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var sampleRate: Int?

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
    player?.stop()
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
        "No audio output is available. Your reply is still available as text.")
    }
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    self.engine = engine
    self.player = player
    sampleRate = requestedRate
    return format
  }
}
