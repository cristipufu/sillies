import SilliesCore
import SilliesTextModels

@testable import SilliesReasoning

protocol NotesTestBackend: ReasoningBackend, ConversationBudgeting {}

extension NotesTestBackend {
  var meetingNotesStyle: MeetingNotesStyle { .synthesized }
  var contextWindowTokens: Int { 4_096 }
  var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    try ConversationTokenEstimate.count(request)
  }
}
