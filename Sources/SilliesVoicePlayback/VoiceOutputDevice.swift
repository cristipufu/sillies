import Foundation
import SilliesTTS

/// A device belongs to one playback actor. Completion means the samples reached the output device.
package protocol VoiceOutputDevice: AnyObject {
  func onInterruption(_ receive: @escaping @Sendable () -> Void)
  func onAudibleOutput(_ receive: @escaping @Sendable (TimeInterval) -> Void)
  func prepare(sampleRate: Int) throws
  func schedule(_ audio: SynthesizedAudio, completed: @escaping @Sendable () -> Void) throws
  func stop()
}
