import CoreGraphics
import Foundation

/// A saved productivity artifact produced by a companion skill.
public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
  private static let permissionIndicators = [
    "screen recording permission",
    "system settings",
    "permission needed",
  ]

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
  public var actionItems: [String]
  public var imageFilename: String?
  public var stashedItems: [String]
  public var summaryPending: Bool
  public var failureMessage: String?
  public var audioFilename: String?
  public var explanation: String
  public var processingNote: String
  public var suggestions: [MeetingSuggestion]
  public var languageIdentifier: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case characterID
    case characterName
    case appName
    case bundleIdentifier
    case windowTitle
    case createdAt
    case durationSeconds
    case transcript
    case extractedText
    case summary
    case actionItems
    case imageFilename
    case stashedItems
    case summaryPending
    case audioFilename, explanation, processingNote, suggestions, failureMessage, languageIdentifier
  }

  public init(
    id: UUID = UUID(), kind: CompanionSkillKind, characterID: String, characterName: String,
    appName: String, bundleIdentifier: String? = nil, windowTitle: String? = nil,
    createdAt: Date = Date(), durationSeconds: Double = 0, transcript: String = "",
    extractedText: String = "", summary: String = "", actionItems: [String] = [],
    imageFilename: String? = nil, stashedItems: [String] = [], summaryPending: Bool = false,
    failureMessage: String? = nil, audioFilename: String? = nil, explanation: String = "",
    processingNote: String = "",
    suggestions: [MeetingSuggestion] = [], languageIdentifier: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.characterID = characterID
    self.characterName = characterName
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.windowTitle = windowTitle
    self.createdAt = createdAt
    self.durationSeconds = durationSeconds
    self.transcript = transcript
    self.extractedText = extractedText
    self.summary = summary
    self.actionItems = actionItems
    self.imageFilename = imageFilename
    self.stashedItems = stashedItems
    self.summaryPending = summaryPending
    self.failureMessage = failureMessage
    self.audioFilename = audioFilename
    self.explanation = explanation
    self.processingNote = processingNote
    self.suggestions = suggestions
    self.languageIdentifier = languageIdentifier
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decode(CompanionSkillKind.self, forKey: .kind)
    characterID = try container.decode(String.self, forKey: .characterID)
    characterName = try container.decode(String.self, forKey: .characterName)
    appName = try container.decode(String.self, forKey: .appName)
    bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
    transcript = try container.decode(String.self, forKey: .transcript)
    extractedText = try container.decode(String.self, forKey: .extractedText)
    summary = try container.decode(String.self, forKey: .summary)
    actionItems = try container.decode([String].self, forKey: .actionItems)
    imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
    stashedItems = try container.decode([String].self, forKey: .stashedItems)
    summaryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryPending) ?? false
    failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
    audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
    explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    processingNote = try container.decodeIfPresent(String.self, forKey: .processingNote) ?? ""
    suggestions =
      try container.decodeIfPresent([MeetingSuggestion].self, forKey: .suggestions) ?? []
    languageIdentifier = try container.decodeIfPresent(String.self, forKey: .languageIdentifier)
  }

  public var requiresPermissionAccess: Bool {
    Self.indicatesPermissionNeeded(summary)
  }

  public static func indicatesPermissionNeeded(_ text: String) -> Bool {
    let lower = text.lowercased()
    return permissionIndicators.contains { lower.contains($0) }
  }

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

  public var markdownExport: String {
    var lines: [String] = [
      "# \(displayTitle)",
      "- **Skill**: \(kind.title)",
      "- **Companion**: \(characterName)",
      "- **Date**: \(createdAt.ISO8601Format())",
    ]
    if durationSeconds >= 1 {
      lines.append("- **Duration**: \(Self.formatDuration(durationSeconds))")
    }
    if let languageIdentifier {
      lines.append(
        "- **Notes language**: \(Locale.current.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier)"
      )
    }
    if !summary.isEmpty {
      lines.append("\n## Summary\n\(summary)")
    }
    if let failureMessage { lines.append("\nSession issue: \(failureMessage)") }
    if let audioFilename { lines.append("\nAudio: \(audioFilename)") }
    if !processingNote.isEmpty { lines.append("\n\(processingNote)") }
    if !explanation.isEmpty { lines.append("\n## Explanation\n\(explanation)") }
    if !suggestions.isEmpty {
      lines.append("\n## Meeting Suggestions")
      for suggestion in suggestions {
        lines.append(
          "- [\(Self.formatDuration(suggestion.elapsed))] \(suggestion.question)\n  Source: \(suggestion.evidence)"
        )
      }
    }
    if !actionItems.isEmpty {
      lines.append("\n## Action Items")
      for item in actionItems {
        lines.append("- [ ] \(item)")
      }
    }
    if !transcript.isEmpty {
      lines.append("\n## Transcript\n\(transcript)")
    }
    if !extractedText.isEmpty {
      lines.append("\n## Extracted Window Text\n```\n\(extractedText)\n```")
    }
    if !stashedItems.isEmpty {
      lines.append("\n## Stashed Items")
      for item in stashedItems {
        lines.append("- \(item)")
      }
    }
    return lines.joined(separator: "\n")
  }

  public static func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let minutes = total / 60
    let remainder = total % 60
    return String(format: "%02d:%02d", minutes, remainder)
  }
}
