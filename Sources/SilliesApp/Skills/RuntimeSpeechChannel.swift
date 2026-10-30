import AVFoundation
import SilliesSpeech

/// Channels keep their model installation leased even if the preparing caller leaves.
final class RuntimeSpeechChannel: LocalSpeechChannel {
  private let channel: any LocalSpeechChannel
  private let runtime: SpeechRuntimeRegistry.Runtime

  init(channel: any LocalSpeechChannel, runtime: SpeechRuntimeRegistry.Runtime) {
    self.channel = channel
    self.runtime = runtime
  }

  func append(_ buffer: AVAudioPCMBuffer) { channel.append(buffer) }
  func finish(completion: @escaping @Sendable () -> Void) { channel.finish(completion: completion) }
  func cancel() { channel.cancel() }
}
