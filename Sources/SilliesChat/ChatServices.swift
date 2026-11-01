import Foundation
import SilliesAudio
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesTTS

package struct ChatSpeechRequest: Sendable {
  package let id: UUID
  package let text: String
  package let profile: CharacterChatProfile
  package init(id: UUID, text: String, profile: CharacterChatProfile) {
    self.id = id
    self.text = text
    self.profile = profile
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
}

extension ChatSpeechOutput {
  package func availabilityNotice(language: String) async -> String? { nil }
}

package struct ChatServices: Sendable {
  package let captureFactory: ConversationCaptureFactory
  package let loadLanguages: @Sendable () async throws -> SpeechLanguageCatalog
  package let conversation: any ConversationResponding
  package let speech: any ChatSpeechOutput
  package let deliver: AudioSessionUpdateDelivery.Schedule

  package init(
    captureFactory: @escaping ConversationCaptureFactory,
    loadLanguages: @escaping @Sendable () async throws -> SpeechLanguageCatalog,
    conversation: any ConversationResponding, speech: any ChatSpeechOutput,
    deliver: @escaping AudioSessionUpdateDelivery.Schedule
  ) {
    self.captureFactory = captureFactory
    self.loadLanguages = loadLanguages
    self.conversation = conversation
    self.speech = speech
    self.deliver = deliver
  }
}
