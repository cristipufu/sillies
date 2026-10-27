import CoreGraphics
import Foundation

/// Productivity skills that a companion can perform when dropped onto a window or given content.
public enum CompanionSkillKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case snap
  case listen
  case watch
  case focus
  case stash

  public var id: Self { self }

  public static let radialSkills: [Self] = [.snap, .listen, .watch, .focus]

  public var title: String {
    switch self {
    case .snap: "Snap & OCR"
    case .listen: "Listen & Scribe"
    case .watch: "Watch Window"
    case .focus: "Focus Sprint"
    case .stash: "Pocket Stash"
    }
  }

  public var shortTitle: String {
    switch self {
    case .snap: "Snap"
    case .listen: "Listen"
    case .watch: "Watch"
    case .focus: "Focus"
    case .stash: "Stash"
    }
  }

  public var symbolName: String {
    switch self {
    case .snap: "camera.viewfinder"
    case .listen: "waveform.badge.mic"
    case .watch: "eye.circle.fill"
    case .focus: "timer"
    case .stash: "tray.and.arrow.down.fill"
    }
  }

  public var activeVerb: String {
    switch self {
    case .snap: "Capturing"
    case .listen: "Transcribing"
    case .watch: "Watching"
    case .focus: "Focusing"
    case .stash: "Stashed"
    }
  }

  public var eventKind: EventKind {
    switch self {
    case .snap: .skillSnap
    case .listen: .skillListen
    case .watch: .skillWatch
    case .focus: .skillFocus
    case .stash: .stashReceived
    }
  }

  public var completionHeadline: String {
    switch self {
    case .snap: "Snapshot & OCR Saved"
    case .listen: "Transcript & Notes Saved"
    case .watch: "Window Activity Detected"
    case .focus: "Focus Sprint Logged"
    case .stash: "Saved to Pocket Stash"
    }
  }

  public var stopActionTitle: String? {
    switch self {
    case .listen: "Finish"
    case .watch, .focus: "Done"
    case .snap, .stash: nil
    }
  }

  public var offersTargetActivationOnCompletion: Bool {
    self == .watch
  }

  public var savesPartialOnCancel: Bool {
    self == .listen || self == .focus
  }
}

/// Metadata for a candidate window under a dragged companion.
public struct WindowTargetCandidate: Equatable, Sendable {
  public let windowID: UInt32
  public let processID: Int32
  public let appName: String
  public let bundleIdentifier: String?
  public let windowTitle: String?
  public var frame: CGRect
  public let windowLayer: Int

  public init(
    windowID: UInt32, processID: Int32, appName: String,
    bundleIdentifier: String? = nil, windowTitle: String? = nil, frame: CGRect,
    windowLayer: Int = 0
  ) {
    self.windowID = windowID
    self.processID = processID
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.windowTitle = windowTitle
    self.frame = frame
    self.windowLayer = windowLayer
  }

  public var displayTitle: String {
    if let windowTitle, !windowTitle.isEmpty, windowTitle != appName {
      return "\(appName) · \(windowTitle)"
    }
    return appName
  }
}

/// Pure geometric layout and hit-testing for the radial skill wheel around a dragged companion.
public struct RadialSkillMenuLayout: Equatable, Sendable {
  public struct Item: Equatable, Sendable, Identifiable {
    public let skill: CompanionSkillKind
    public let center: CGPoint
    public var id: CompanionSkillKind { skill }
  }

  public static let orbitRadius: Double = 88
  public static let bubbleHitRadius: Double = 36
  public static let screenMargin: Double = 96
  private static let topFlipClearanceMargin: Double = 12
  private static let upwardAnglesDegrees: [Double] = [148, 109, 71, 32]
  private static let downwardAnglesDegrees: [Double] = [-148, -109, -71, -32]

  public let anchor: CGPoint
  public let items: [Item]

  public init(
    center: CGPoint, visibleFrame: CGRect,
    skills: [CompanionSkillKind] = CompanionSkillKind.radialSkills
  ) {
    let clampedX = min(
      max(center.x, visibleFrame.minX + Self.screenMargin),
      visibleFrame.maxX - Self.screenMargin)
    let clampedY = min(
      max(center.y, visibleFrame.minY + Self.screenMargin),
      visibleFrame.maxY - Self.screenMargin)
    let clampedAnchor = CGPoint(x: clampedX, y: clampedY)
    anchor = clampedAnchor
    let flipDownward =
      clampedAnchor.y + Self.orbitRadius + Self.bubbleHitRadius
      > visibleFrame.maxY - Self.topFlipClearanceMargin
    let angles = flipDownward ? Self.downwardAnglesDegrees : Self.upwardAnglesDegrees
    items = zip(skills, angles).map { skill, degrees in
      let radians = degrees * .pi / 180
      let itemCenter = CGPoint(
        x: clampedAnchor.x + cos(radians) * Self.orbitRadius,
        y: clampedAnchor.y + sin(radians) * Self.orbitRadius)
      return Item(skill: skill, center: itemCenter)
    }
  }

  public func selectedSkill(at pointer: CGPoint) -> CompanionSkillKind? {
    items.min {
      hypot($0.center.x - pointer.x, $0.center.y - pointer.y)
        < hypot($1.center.x - pointer.x, $1.center.y - pointer.y)
    }.flatMap { nearest in
      hypot(nearest.center.x - pointer.x, nearest.center.y - pointer.y) <= Self.bubbleHitRadius
        ? nearest.skill : nil
    }
  }
}

/// Lifecycle state of a companion's attachment to a specific window task.
public enum CompanionBindingState: Equatable, Sendable {
  case followingFocusedWindow
  case awaitingSelection(target: WindowTargetCandidate, expiresAt: TimeInterval)
  case active(
    target: WindowTargetCandidate, skill: CompanionSkillKind, startedAt: TimeInterval,
    statusDetail: String = "", audioLevel: Double = 0)
  case completed(
    target: WindowTargetCandidate, skill: CompanionSkillKind, summary: String,
    recordID: UUID, expiresAt: TimeInterval)

  public var boundTarget: WindowTargetCandidate? {
    switch self {
    case .followingFocusedWindow: nil
    case .awaitingSelection(let target, _),
      .active(let target, _, _, _, _),
      .completed(let target, _, _, _, _):
      target
    }
  }

  public var isBound: Bool { boundTarget != nil }
}

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
  }

  public init(
    id: UUID = UUID(), kind: CompanionSkillKind, characterID: String, characterName: String,
    appName: String, bundleIdentifier: String? = nil, windowTitle: String? = nil,
    createdAt: Date = Date(), durationSeconds: Double = 0, transcript: String = "",
    extractedText: String = "", summary: String = "", actionItems: [String] = [],
    imageFilename: String? = nil, stashedItems: [String] = [], summaryPending: Bool = false
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
    if !summary.isEmpty {
      lines.append("\n## Summary\n\(summary)")
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
