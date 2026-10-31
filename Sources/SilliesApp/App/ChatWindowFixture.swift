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
    let session = ChatSession(
      companionName: "Mochi", profile: .init(personality: "Warm and playful"),
      services: .init(
        captureFactory: { _, _ in UnavailableMicrophone() },
        loadLanguages: { .init(languages: []) },
        conversation: conversation, speech: SilentVoice(),
        deliver: { MainRunLoopDelivery.perform($0) }))
    session.spokenReplies = false
    session.draft = "Can you keep me company while I finish my work?"
    session.send()
    return session
  }

  private struct Reply: ConversationResponding {
    func reply(to context: ChatContext) async throws -> String {
      "Of course. I’ll keep this corner warm. What are you working on?"
    }
  }

  private struct SilentVoice: ChatSpeechOutput {
    func speak(
      _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
    ) async throws -> String? { nil }
    func stop(id: UUID) async {}
  }

  private final class UnavailableMicrophone: SessionAudioCapture, Sendable {
    func start() {}
    func pause() {}
    func resume() {}
    func changeLanguage(_ language: SpeechLanguage) {}
    func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
      completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
    }
  }
}
