import Foundation
import SilliesCore

/// Configuration checks do not prepare inference or request a permission prompt.
package enum ChatReadiness: Sendable {
  case unchecked, checking, available
  case needsSetup(ChatNotice)
  case permissionRequired(SessionFailure)

  package var notice: ChatNotice? {
    guard case .needsSetup(let notice) = self else { return nil }
    return notice
  }

  static func resolve(services: ChatServices, language: String, mode: ConversationMode) async
    -> Self
  {
    await ConversationReadiness.evaluate(services: services, language: language, mode: mode)
      .admission
  }
}
