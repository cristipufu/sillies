import AVFoundation

/// Channel completion includes returning its engine; cancellation never makes busy state reusable.
package final class LeasedSpeechChannel: LocalSpeechChannel {
  private let channel: any LocalSpeechChannel
  private let lease: SpeechEngineLease

  package init(channel: any LocalSpeechChannel, lease: SpeechEngineLease) {
    self.channel = channel
    self.lease = lease
  }

  deinit {
    channel.cancel()
    Task { [lease] in await lease.release() }
  }

  package func append(_ buffer: AVAudioPCMBuffer) { channel.append(buffer) }

  package func finish(completion: @escaping @Sendable () -> Void) {
    channel.finish { [lease] in
      Task {
        await lease.release()
        completion()
      }
    }
  }

  package func cancel() {
    channel.cancel()
    Task { [lease] in await lease.release() }
  }
}
