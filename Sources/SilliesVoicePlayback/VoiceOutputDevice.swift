import SilliesTTS

/// A device belongs to one playback actor. Completion means the samples reached the output device.
package protocol VoiceOutputDevice: AnyObject {
  func onInterruption(_ receive: @escaping @Sendable () -> Void)
  func schedule(_ audio: SynthesizedAudio, completed: @escaping @Sendable () -> Void) throws
  func stop()
}
