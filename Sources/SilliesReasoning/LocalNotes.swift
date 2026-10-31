import SilliesCore

/// Derived text and its provenance travel together without changing the source record.
package struct LocalNotes: Sendable {
  package struct Provenance: Sendable {
    package let source: SessionNotesSource
    package let notice: String
    package init(source: SessionNotesSource = .unspecified, notice: String = "") {
      self.source = source
      self.notice = notice
    }
  }
  package let summary: String
  package let actions: [String]
  package let explanation: String
  package let provenance: Provenance
  package var notice: String { provenance.notice }
  package var source: SessionNotesSource { provenance.source }

  package init(
    summary: String, actions: [String], explanation: String = "", provenance: Provenance = .init()
  ) {
    self.summary = summary
    self.actions = actions
    self.explanation = explanation
    self.provenance = provenance
  }
}
