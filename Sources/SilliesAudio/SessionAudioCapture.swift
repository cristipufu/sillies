import Foundation
import SilliesCore
import SilliesSpeech

package protocol SessionAudioCapture: AnyObject, Sendable {
  func start()
  func pause()
  func resume()
  func changeLanguage(_ language: SpeechLanguage)
  func refreshProgress()
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void)
  func finish(
    ending reason: SessionEndReason, completion: @escaping @Sendable (AudioCaptureResult) -> Void)
}

extension SessionAudioCapture {
  package func finish(
    ending reason: SessionEndReason, completion: @escaping @Sendable (AudioCaptureResult) -> Void
  ) {
    finish { completion($0.ending(reason)) }
  }
}

package typealias SessionAudioCaptureFactory =
  @Sendable (
    AudioCaptureConfiguration, @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) -> any SessionAudioCapture

extension SessionAudioCapture {
  package func refreshProgress() {}
}
