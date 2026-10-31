import Foundation

/// A saved productivity artifact produced by a companion skill.
public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let kind: CompanionSkillKind
  public let characterID: String
  public let characterName: String
  public let appName: String
  public let bundleIdentifier: String?
  public let windowTitle: String?
  public let createdAt: Date
  public var durationSeconds: Double
  public var transcript: String
  public var extractedText: String
  public var summary: String
  public var notesNotice = ""
  public var notesSource = SessionNotesSource.unspecified
  public var actionItems: [String]
  public var imageFilename: String?
  public var stashedItems: [String]
  public var summaryPending: Bool
  public let failure: SessionFailure?
  public var failureMessage: String? { failure?.message }
  public var audioFilename: String?
  public var explanation: String
  public var processingNote: String
  public var suggestions: [MeetingSuggestion]
  public var languageIdentifier: String?
  public let speechProvenance: SpeechProvenance?
  public let diarizationProvenance: SpeechProvenance?
  public var isProtected = false
  public var screenshotTextState = ScreenshotTextState.none
  public var transcriptSegments: [TranscriptSegment] = []
  public var speakerNames: [String: String] = [:]
  public var originalSpeakerTranscript: String?
  public var processingRevision: SessionProcessingRevision

  public init(
    kind: CompanionSkillKind, origin: SessionOrigin, content: SessionContent = .init(),
    metadata: SessionMetadata = .init()
  ) {
    self.id = metadata.id
    self.processingRevision = .init(seed: metadata.id)
    self.kind = kind
    self.characterID = origin.characterID
    self.characterName = origin.characterName
    self.appName = origin.source.appName
    self.bundleIdentifier = origin.source.bundleIdentifier
    self.windowTitle = origin.source.windowTitle
    self.createdAt = metadata.createdAt
    self.durationSeconds = metadata.durationSeconds
    self.languageIdentifier = metadata.transcription.languageIdentifier
    self.speechProvenance = metadata.transcription.provenance
    self.diarizationProvenance = metadata.transcription.diarizationProvenance
    self.transcript = content.text.transcript
    self.transcriptSegments = content.text.segments
    self.extractedText = content.text.extractedText
    self.stashedItems = content.text.stashedItems
    self.summary = content.notes.summary
    self.actionItems = content.notes.actionItems
    self.explanation = content.notes.explanation
    self.suggestions = content.notes.suggestions
    self.imageFilename = content.attachments.imageFilename
    self.audioFilename = content.attachments.audioFilename
    self.summaryPending = content.processing.summaryPending
    self.failure = content.processing.failure
    self.processingNote = content.processing.note
  }

  public var requiresPermissionAccess: Bool { failure?.recovery != nil }

  public var primaryText: String {
    if !transcript.isEmpty { return transcript }
    if !extractedText.isEmpty { return extractedText }
    if !stashedItems.isEmpty { return stashedItems.joined(separator: "\n") }
    return summary
  }

  public var displayTitle: String {
    if let windowTitle, !windowTitle.isEmpty, windowTitle != appName {
      return "\(appName) — \(windowTitle)"
    }
    return "\(appName) · \(kind.title)"
  }

  public static func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let minutes = total / 60
    let remainder = total % 60
    return String(format: "%02d:%02d", minutes, remainder)
  }
}
