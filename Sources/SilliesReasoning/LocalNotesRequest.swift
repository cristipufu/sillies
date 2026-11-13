import SilliesCore

/// Personal notes guide emphasis; only the source establishes what happened.
package struct LocalNotesRequest: Sendable {
  package let source: String
  package let kind: CompanionSkillKind
  package let fallback: String
  package let personalNotes: String
  package let localeIdentifier: String?

  package init(
    source: String, kind: CompanionSkillKind, fallback: String,
    personalNotes: String = "", localeIdentifier: String? = nil
  ) {
    self.source = source
    self.kind = kind
    self.fallback = fallback
    self.personalNotes = personalNotes
    self.localeIdentifier = localeIdentifier
  }
}
