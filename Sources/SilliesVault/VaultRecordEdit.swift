import Foundation
import SilliesCore
import SilliesReasoning

/// Field-level commands never replace unrelated content from a stale UI snapshot.
package enum VaultRecordEdit: Sendable {
  package enum Protection: Sendable, Equatable { case protected, unprotected }
  package struct SpeakerEdit: Sendable {
    package let expectedRevision: UUID
    package let transcript: String
    package let names: [String: String]
    package let originalTranscript: String?
    package init(original: SessionRecord, renamed: SessionRecord) {
      expectedRevision = original.processingRevision.notes
      transcript = renamed.transcript
      names = renamed.speakerNames
      originalTranscript = renamed.originalSpeakerTranscript
    }
  }
  case protection(Protection)
  case requestNotes
  case renameSpeaker(SpeakerEdit)
  case completeNotes(LocalNotes, revision: UUID)
  case retryScreenshot
  case completeScreenshot(text: String, revision: UUID)
  case failScreenshot(message: String, revision: UUID)

  package var requestsNotes: Bool {
    switch self {
    case .requestNotes, .renameSpeaker: true
    default: false
    }
  }
  package var requestsScreenshot: Bool {
    if case .retryScreenshot = self { true } else { false }
  }
  package func apply(to record: inout SessionRecord) -> Bool {
    switch self {
    case .protection(let protection):
      record.isProtected = protection == .protected
    case .requestNotes:
      requestNotes(in: &record)
    case .renameSpeaker(let edit):
      guard record.processingRevision.notes == edit.expectedRevision else { return false }
      record.transcript = edit.transcript
      record.speakerNames = edit.names
      record.originalSpeakerTranscript = edit.originalTranscript
      requestNotes(in: &record)
    case .completeNotes(let notes, let revision):
      guard record.summaryPending, record.processingRevision.notes == revision else { return false }
      record.summary = notes.summary
      record.notesSource = notes.source
      record.actionItems = notes.actions
      record.explanation = notes.explanation
      record.notesNotice = notes.notice
      record.summaryPending = false
    case .retryScreenshot:
      record.processingRevision.renewScreenshot()
      record.screenshotTextState = .pending
    case .completeScreenshot(let text, let revision):
      guard acceptsScreenshot(record, revision: revision) else { return false }
      record.extractedText = text
      record.screenshotTextState = .complete
      record.processingNote = text.isEmpty ? "No readable text was found in this screenshot." : ""
    case .failScreenshot(let message, let revision):
      guard acceptsScreenshot(record, revision: revision) else { return false }
      record.screenshotTextState = .failed
      record.processingNote = message
    }
    return true
  }
  private func requestNotes(in record: inout SessionRecord) {
    record.processingRevision.renewNotes()
    record.summaryPending = true
  }
  private func acceptsScreenshot(_ record: SessionRecord, revision: UUID) -> Bool {
    record.screenshotTextState == .pending && record.processingRevision.screenshot == revision
  }
}
