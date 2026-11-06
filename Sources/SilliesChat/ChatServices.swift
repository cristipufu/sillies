import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import SilliesReasoning
import SilliesSpeech
import SilliesTTS

package struct ChatSpeechRequest: Sendable {
  package let id: UUID
  package let text: String
  package let profile: CharacterChatProfile
  package let lifetime: SpeechModelLifetime?
  package init(
    id: UUID, text: String, profile: CharacterChatProfile, lifetime: SpeechModelLifetime? = nil
  ) {
    self.id = id
    self.text = text
    self.profile = profile
    self.lifetime = lifetime
  }
}

/// Returns a text-only explanation when no installed voice supports the conversation.
package protocol ChatSpeechOutput: Sendable {
  func availabilityNotice(language: String) async -> String?
  func speak(
    _ request: ChatSpeechRequest,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String?
  func stop(id: UUID) async
  func pause(id: UUID) async
  func resume(id: UUID) async
  func speakStream(
    _ request: ChatSpeechRequest, text: SpeechTextStream,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String?
}

extension ChatSpeechOutput {
  package func speakStream(
    _ request: ChatSpeechRequest, text: SpeechTextStream,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    while let phrase = try await text.next() {
      if let notice = try await speak(
        .init(id: request.id, text: phrase, profile: request.profile, lifetime: request.lifetime),
        receive: receive)
      {
        return notice
      }
      receive(.utteranceFinished(phrase))
    }
    return nil
  }
  package func availabilityNotice(language: String) async -> String? { nil }
}

package struct ChatServices: Sendable {
  package let captureFactory: ConversationCaptureFactory
  package let loadLanguages: @Sendable () async throws -> SpeechLanguageCatalog
  package let conversation: any ConversationResponding
  package let speech: any ChatSpeechOutput
  package let deliver: AudioSessionUpdateDelivery.Schedule
  package let history: ChatHistoryConfiguration
  package let diagnostics: DiagnosticSink
  package let microphonePermission: @Sendable () -> SessionFailure?

  package init(
    captureFactory: @escaping ConversationCaptureFactory,
    loadLanguages: @escaping @Sendable () async throws -> SpeechLanguageCatalog,
    conversation: any ConversationResponding, speech: any ChatSpeechOutput,
    deliver: @escaping AudioSessionUpdateDelivery.Schedule, history: ChatHistoryConfiguration,
    diagnostics: DiagnosticSink = .disabled,
    microphonePermission: @escaping @Sendable () -> SessionFailure? = { nil }
  ) {
    self.captureFactory = captureFactory
    self.loadLanguages = loadLanguages
    self.conversation = conversation
    self.speech = speech
    self.deliver = deliver
    self.history = history
    self.diagnostics = diagnostics
    self.microphonePermission = microphonePermission
  }
}
