import Foundation

/// One saved generation input, including the authored context and its source revisions.
public struct VaultNotesInput: Sendable {
  public struct Revision: Equatable, Sendable {
    public let generation: UUID
    public let transcript: UUID?
    public let screenshotText: UUID?
    public let personalNotes: UUID?

    public init(generation: UUID, transcript: UUID?, screenshotText: UUID?, personalNotes: UUID?) {
      self.generation = generation
      self.transcript = transcript
      self.screenshotText = screenshotText
      self.personalNotes = personalNotes
    }
  }
  public let record: SessionRecord
  public let personalNotes: String
  public let revision: Revision

  public init(record: SessionRecord, personalNotes: String, revision: Revision) {
    self.record = record
    self.personalNotes = personalNotes
    self.revision = revision
  }
}
