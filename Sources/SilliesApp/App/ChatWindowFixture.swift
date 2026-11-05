import Foundation
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesTTS

/// Native window checks exercise the real Chat view without model downloads or microphone access.
@MainActor enum ChatWindowFixture {
  static func makeSession() -> ChatSession {
    makeSession(conversation: Reply())
  }

  static func makeSession(conversation: any ConversationResponding) -> ChatSession {
    let session = makeReadySession(conversation: conversation)
    session.draft = "Can you keep me company while I finish my work?"
    session.send()
    return session
  }

  static func makeReadySession(conversation: any ConversationResponding) -> ChatSession {
    makeReadySession(
      conversation: conversation, history: .transient, owner: .init(id: "mochi", name: "Mochi"))
  }

  static func makeReadySession(
    conversation: any ConversationResponding, history: ChatHistoryConfiguration,
    owner: ConversationOwner
  ) -> ChatSession {
    let session = ChatSession(
      companionName: owner.name, profile: .init(personality: "Warm and playful"),
      services: .init(
        captureFactory: { _, _ in UnavailableMicrophone() },
        loadLanguages: { .init(languages: []) },
        conversation: conversation, speech: SilentVoice(),
        deliver: { MainRunLoopDelivery.perform($0) }, history: history), companionID: owner.id)
    session.spokenReplies = false
    return session
  }

  private struct Reply: ConversationResponding {
    func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
      async throws -> ChatReply
    {
      .init(text: "Of course. I’ll keep this corner warm. What are you working on?")
    }
  }

  private struct SilentVoice: ChatSpeechOutput {
    func speak(
      _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
    ) async throws -> String? { nil }
    func stop(id: UUID) async {}
    func pause(id: UUID) async {}
    func resume(id: UUID) async {}
  }

  private final class UnavailableMicrophone: ConversationCapture, Sendable {
    func start() {}
    func pause() {}
    func resume() {}
    func changeLanguage(_ language: SpeechLanguage) {}
    func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
      finish(completion: completion)
    }
    func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
      completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
    }
  }
}
