import Foundation
import SilliesChat
import SilliesCore

@MainActor final class ChatSkillSession: ActiveSkillSession {
  let presentation: ChatSession
  var initialStatusDetail: String { presentation.status }

  init(presentation: ChatSession) { self.presentation = presentation }
  func start() {}
  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    .keepRunning(statusDetail: presentation.status, audioLevel: presentation.audioLevel)
  }
  func finish(
    _ context: SkillFinalizeContext,
    completion: @escaping @MainActor (SkillCompletionOutcome?) -> Void
  ) {
    presentation.finish { [presentation] in
      let draft = presentation.draft.trimmingCharacters(in: .whitespacesAndNewlines)
      let transcript = [
        presentation.transcript, draft.isEmpty ? "" : String(localized: "You (unsent)\n\(draft)"),
      ]
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
      guard !transcript.isEmpty else {
        completion(nil)
        return
      }
      let record = SessionRecord(
        kind: .chat,
        origin: .init(
          characterID: context.companionID, characterName: context.companionName,
          source: .init(appName: context.companionName)),
        content: .init(
          text: .init(transcript: transcript),
          notes: .init(summary: String(localized: "A conversation with \(context.companionName)."))),
        metadata: .init(
          durationSeconds: max(0, context.now - context.startedAt),
          transcription: .init(languageIdentifier: presentation.language)))
      completion(
        .init(
          record: record, image: nil, bannerSummary: String(localized: "Chat saved · Open Vault")))
    }
  }
  func cancel() { presentation.finish {} }
}
