import Foundation
import SilliesChat
import SilliesCore

@MainActor final class ConversationActivity: ActiveSkillSession {
  let presentation: ChatSession
  var initialStatusDetail: String { presentation.status }

  init(presentation: ChatSession) { self.presentation = presentation }
  func start() {
    presentation.showChat()
    Task { await presentation.restoreHistory() }
  }
  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    .keepRunning(statusDetail: presentation.status, audioLevel: presentation.audioLevel)
  }
  func finish(
    _ context: SkillFinalizeContext,
    completion: @escaping @MainActor (SkillCompletionOutcome?) -> Void
  ) {
    presentation.finish { completion(nil) }
  }

  func cancel() { presentation.finish {} }
}
