import SilliesAudio
import SilliesSpeech

package struct WritingCaptureServices: Sendable {
  package let factory: SessionAudioCaptureFactory
  package let loadLanguages: @Sendable () async throws -> SpeechLanguageCatalog
  package let deliver: AudioSessionUpdateDelivery.Schedule
  package init(
    factory: @escaping SessionAudioCaptureFactory,
    loadLanguages: @escaping @Sendable () async throws -> SpeechLanguageCatalog,
    deliver: @escaping AudioSessionUpdateDelivery.Schedule
  ) {
    self.factory = factory
    self.loadLanguages = loadLanguages
    self.deliver = deliver
  }
}
