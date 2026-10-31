import Foundation
import SilliesCore

/// Application-facing capabilities. Implementations receive their backend from the composition root.
package protocol LocalReasoning: Sendable {
  func availabilityNotice(localeIdentifier: String?) async -> String?
  func notes(
    for text: String, kind: CompanionSkillKind, fallback: String, localeIdentifier: String?
  ) async -> LocalNotes
  func suggestion(source: String, elapsed: TimeInterval, localeIdentifier: String?) async
    -> MeetingSuggestion?
  func transform(_ text: String, operation: LocalTextOperation) async throws -> String
}
