import Foundation
import SilliesCore

/// Queue metadata only. Never retain a transcript or a model while waiting for idle time.
struct ConversationCheckpointJob: Sendable {
  let handle: ConversationHandle
  let sessionID: UUID
  let beforeMessageID: UUID
  let languageIdentifier: String

  init?(_ context: ChatContext) {
    guard let handle = context.historyHandle, let session = context.sessionID,
      let current = context.messages.last, current.role == .user
    else { return nil }
    self.handle = handle
    sessionID = session
    beforeMessageID = current.id
    languageIdentifier = context.profile.languageIdentifier
  }
}
