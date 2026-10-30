import Foundation
import SilliesSpeech

package protocol SessionAudioCapture: AnyObject, Sendable {
  func start()
  func pause()
  func resume()
  func changeLanguage(_ language: SpeechLanguage)
  func refreshProgress()
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void)
}

package typealias SessionAudioCaptureFactory =
  @Sendable (
    AudioCaptureConfiguration, @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) -> any SessionAudioCapture

extension SessionAudioCapture {
  package func refreshProgress() {}
}
