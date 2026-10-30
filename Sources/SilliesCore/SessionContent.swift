/// Construction inputs grouped by source material, derived notes, files, and processing state.
/// The persisted record keeps its existing flat schema.
public struct SessionContent: Sendable {
  public struct Text: Sendable {
    public let transcript: String
    public let extractedText: String
    public let stashedItems: [String]

    public init(transcript: String = "", extractedText: String = "", stashedItems: [String] = []) {
      self.transcript = transcript
      self.extractedText = extractedText
      self.stashedItems = stashedItems
    }
  }

  public struct Notes: Sendable {
    public let summary: String
    public let actionItems: [String]
    public let explanation: String
    public let suggestions: [MeetingSuggestion]

    public init(
      summary: String = "", actionItems: [String] = [], explanation: String = "",
      suggestions: [MeetingSuggestion] = []
    ) {
      self.summary = summary
      self.actionItems = actionItems
      self.explanation = explanation
      self.suggestions = suggestions
    }
  }

  public struct Attachments: Sendable {
    public let imageFilename: String?
    public let audioFilename: String?

    public init(imageFilename: String? = nil, audioFilename: String? = nil) {
      self.imageFilename = imageFilename
      self.audioFilename = audioFilename
    }
  }

  public struct Processing: Sendable {
    public let summaryPending: Bool
    public let failure: SessionFailure?
    public let note: String

    public init(summaryPending: Bool = false, failure: SessionFailure? = nil, note: String = "") {
      self.summaryPending = summaryPending
      self.failure = failure
      self.note = note
    }
  }

  public let text: Text
  public let notes: Notes
  public let attachments: Attachments
  public let processing: Processing

  public init(
    text: Text = .init(), notes: Notes = .init(), attachments: Attachments = .init(),
    processing: Processing = .init()
  ) {
    self.text = text
    self.notes = notes
    self.attachments = attachments
    self.processing = processing
  }
}
