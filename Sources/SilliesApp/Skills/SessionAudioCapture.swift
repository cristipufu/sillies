import Foundation

protocol SessionAudioCapture: AnyObject, Sendable {
  func start()
  func pause()
  func resume()
  func changeLanguage(_ language: SpeechLanguage)
  func refreshProgress()
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void)
}

typealias SessionAudioCaptureFactory =
  @Sendable (
    AudioCaptureConfiguration, @escaping @Sendable (AudioTranscriptionService.Update) -> Void
  ) -> any SessionAudioCapture

extension SessionAudioCapture {
  func refreshProgress() {}
}
