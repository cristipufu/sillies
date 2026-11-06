import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesDiagnostics
import SilliesReasoning
import SilliesVault

/// One service set per companion; setup inspects the same services used by its conversation.
@MainActor final class ConversationComposition {
  struct Dependencies {
    let speech: SpeechServices
    let voices: VoiceServices
    let reasoning: ReasoningServices
    let conversations: ConversationLibrary
    let vault: VaultLibrary
    let preferences: CompanionPreferences
    let diagnostics: DiagnosticSink
  }
  private let dependencies: Dependencies
  private let reference: VoicePlaybackReference
  private var services: [String: ChatServices] = [:]

  init(dependencies: Dependencies, reference: VoicePlaybackReference) {
    self.dependencies = dependencies
    self.reference = reference
  }

  func services(for id: String) -> ChatServices {
    if let existing = services[id] { return existing }
    let dependencies = dependencies
    let conversations = dependencies.conversations
    let conversation = dependencies.reasoning.makeConversation(
      tools: [
        VaultSearchTool(library: dependencies.vault), VaultReadTool(library: dependencies.vault),
      ],
      history: .init(
        repository: conversations,
        tools: { context in
          ConversationHistoryTools(conversations: conversations, memories: conversations).tools(
            for: context)
        },
        background: .init(materials: dependencies.vault, personalFacts: conversations)),
      modelSelection: { await dependencies.preferences.customization(for: id).textModelID })
    let created = ChatServices(
      captureFactory: dependencies.speech.conversationCaptureFactory(reference: reference),
      loadLanguages: dependencies.speech.languages.load,
      conversation: conversation, speech: dependencies.voices.speech,
      deliver: { MainRunLoopDelivery.perform($0) },
      history: .stored(conversations: conversations, memories: conversations),
      diagnostics: dependencies.diagnostics,
      microphonePermission: MicrophoneAuthorization.failure,
      context: .init(materials: dependencies.vault, personalFacts: conversations))
    services[id] = created
    return created
  }
}
