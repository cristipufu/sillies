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

  public init(
    windowID: UInt32, processID: Int32, appName: String,
    bundleIdentifier: String? = nil, windowTitle: String? = nil, frame: CGRect
  ) {
    self.windowID = windowID
    self.processID = processID
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.windowTitle = windowTitle
    self.frame = frame
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
      clampedAnchor.y + Self.orbitRadius + Self.bubbleHitRadius > visibleFrame.maxY - 12
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

/// Deterministic on-device summarizer and action-item extractor for transcripts and OCR captures.
/// Processes arbitrarily long transcripts in bounded chunks so late action items are never dropped.
public enum SessionSummarizer: Sendable {
  private static let maxSummarySentences = 3
  private static let maxActionItems = 5
  public static let chunkCharacterSize = 16_384
  public static let maxChunkLookahead = 256
  public static let maxFragmentCharacters = 240
  public static let fragmentOverlapCharacters = 32
  public static let maxSummaryCharacters = 600
  private static let sentenceDelimiters = CharacterSet.newlines.union(
    CharacterSet(charactersIn: ".!?"))
  private static let highSignalActionKeywords = [
    "todo", "to-do", "action item", "next step", "deadline",
  ]
  private static let leadActionKeywords: Set<String> = [
    "todo", "to-do", "action item", "next step", "we should", "let's", "follow up",
  ]
  private static let actionKeywords = [
    "todo", "to-do", "action item", "need to", "needs to", "we should", "let's", "must",
    "follow up", "deadline", "next step", "will send", "will fix",
  ]
  private static let priorityKeywords = [
    "decided", "important", "key", "summary", "conclusion", "issue", "bug", "release",
    "launch", "goal", "plan", "result", "error", "update", "question",
  ]

  private struct ScoredEntry {
    let index: Int
    let sourceStart: String.Index
    let score: Double
    let text: String
  }

  private struct ActionKeywordMatch {
    let keyword: String
    let range: Range<String.Index>
  }

  public static func summarize(text: String, fallbackContext: String) -> (
    summary: String, actionItems: [String]
  ) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      return (fallbackContext, [])
    }

    var topSentences: [ScoredEntry] = []
    var topActions: [ScoredEntry] = []
    var sentenceIndex = 0
    var lastActionEndIndex: String.Index?

    forEachChunk(in: cleaned) { chunk in
      forEachSentenceSlice(in: chunk) { sentence in
        forEachBoundedFragment(in: sentence) { fragment, detectionRange in
          let currentIndex = sentenceIndex
          let fragmentText = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
          if fragmentText.count >= 12 {
            sentenceIndex += 1
            let summaryText = String(fragmentText.prefix(maxFragmentCharacters))
            let summaryLower = summaryText.lowercased()
            let summaryScore = scoreSummarySentence(
              sentence: summaryText, lower: summaryLower, index: currentIndex)
            insertSummary(
              ScoredEntry(
                index: currentIndex,
                sourceStart: fragment.startIndex,
                score: summaryScore,
                text: summaryText),
              into: &topSentences)
          }

          while let match = findFirstActionMatch(
            in: cleaned, range: detectionRange, after: lastActionEndIndex)
          {
            let actionRange = extractActionRange(
              in: cleaned,
              sentence: sentence,
              match: match,
              minStart: detectionRange.lowerBound)
            lastActionEndIndex = actionRange.upperBound
            let actionText = String(
              cleaned[actionRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maxFragmentCharacters))
            guard actionText.count >= 12,
              let actionScore = scoreActionItem(lower: actionText.lowercased())
            else { continue }
            insertAction(
              ScoredEntry(
                index: currentIndex,
                sourceStart: actionRange.lowerBound,
                score: actionScore,
                text: actionText),
              into: &topActions)
          }
        }
      }
    }

    guard sentenceIndex > 0 || !topActions.isEmpty else {
      let snippet = String(cleaned.prefix(180))
      return (snippet, [])
    }

    let orderedSummary =
      topSentences
      .sorted { $0.index < $1.index }
      .map { String($0.text.prefix(maxFragmentCharacters)) }
    let orderedActions =
      topActions
      .sorted { $0.sourceStart < $1.sourceStart }
      .map { String($0.text.prefix(maxFragmentCharacters)) }

    let joinedSummary =
      orderedSummary.isEmpty
      ? String(cleaned.prefix(200))
      : orderedSummary.map { "• \($0)" }.joined(separator: "\n")
    let summary = String(joinedSummary.prefix(maxSummaryCharacters))
    return (summary, orderedActions)
  }

  /// Processes arbitrarily long transcripts in chunks on a background worker.
  public static func summarizeOnWorker(
    text: String, fallbackContext: String
  ) async -> (summary: String, actionItems: [String]) {
    await Task.detached(priority: .userInitiated) {
      dispatchPrecondition(condition: .notOnQueue(.main))
      return summarize(text: text, fallbackContext: fallbackContext)
    }.value
  }

  private static func forEachChunk(in text: String, body: (Substring) -> Void) {
    var start = text.startIndex
    while start < text.endIndex {
      let targetEnd =
        text.index(start, offsetBy: chunkCharacterSize, limitedBy: text.endIndex)
        ?? text.endIndex
      var end = targetEnd
      var splitAtDelimiter = false
      if end < text.endIndex {
        let lookaheadLimit =
          text.index(targetEnd, offsetBy: maxChunkLookahead, limitedBy: text.endIndex)
          ?? text.endIndex
        var cursor = targetEnd
        var delimiterSplit: String.Index?
        var whitespaceSplit: String.Index?
        while cursor < lookaheadLimit {
          if let scalar = text[cursor].unicodeScalars.first {
            if sentenceDelimiters.contains(scalar) {
              delimiterSplit = text.index(after: cursor)
              splitAtDelimiter = true
              break
            }
            if whitespaceSplit == nil && CharacterSet.whitespaces.contains(scalar) {
              whitespaceSplit = text.index(after: cursor)
            }
          }
          cursor = text.index(after: cursor)
        }
        end = delimiterSplit ?? whitespaceSplit ?? targetEnd
      }
      body(text[start..<end])
      if end < text.endIndex && !splitAtDelimiter {
        let minAdvance =
          text.index(start, offsetBy: chunkCharacterSize / 2, limitedBy: end) ?? end
        start = overlapStartIndex(in: text[start..<end], before: end, minIndex: minAdvance)
      } else {
        start = end
      }
    }
  }

  private static func forEachSentenceSlice(in chunk: Substring, body: (Substring) -> Void) {
    var cursor = chunk.startIndex
    var segmentStart = cursor
    while cursor < chunk.endIndex {
      if let scalar = chunk[cursor].unicodeScalars.first,
        sentenceDelimiters.contains(scalar)
      {
        if segmentStart < cursor {
          body(chunk[segmentStart..<cursor])
        }
        cursor = chunk.index(after: cursor)
        segmentStart = cursor
      } else {
        cursor = chunk.index(after: cursor)
      }
    }
    if segmentStart < chunk.endIndex {
      body(chunk[segmentStart..<chunk.endIndex])
    }
  }

  private static func forEachBoundedFragment(
    in raw: Substring,
    body: (_ fragment: Substring, _ detectionRange: Range<String.Index>) -> Void
  ) {
    var sliceStart = raw.startIndex
    var previousSliceStart = raw.startIndex
    var isFirstFragment = true
    while sliceStart < raw.endIndex {
      while sliceStart < raw.endIndex && raw[sliceStart].isWhitespace {
        sliceStart = raw.index(after: sliceStart)
      }
      guard sliceStart < raw.endIndex else { break }

      let detectionStart =
        isFirstFragment
        ? sliceStart
        : overlapStartIndex(in: raw, before: sliceStart, minIndex: previousSliceStart)

      guard
        let windowEnd = raw.index(
          sliceStart, offsetBy: maxFragmentCharacters, limitedBy: raw.endIndex)
      else {
        body(raw[sliceStart..<raw.endIndex], detectionStart..<raw.endIndex)
        break
      }

      var splitIndex = windowEnd
      let minBreak =
        raw.index(sliceStart, offsetBy: maxFragmentCharacters / 2, limitedBy: windowEnd)
        ?? sliceStart
      var probe = windowEnd
      while probe > minBreak {
        let previous = raw.index(before: probe)
        if raw[previous].isWhitespace {
          splitIndex = previous
          break
        }
        probe = previous
      }
      body(raw[sliceStart..<splitIndex], detectionStart..<splitIndex)
      previousSliceStart = sliceStart
      sliceStart = splitIndex
      isFirstFragment = false
    }
  }

  private static func findFirstActionMatch(
    in text: String,
    range: Range<String.Index>,
    after lastActionEndIndex: String.Index?
  ) -> ActionKeywordMatch? {
    var best: ActionKeywordMatch?
    for keyword in actionKeywords {
      var searchStart = range.lowerBound
      while searchStart < range.upperBound,
        let found = text.range(
          of: keyword,
          options: [.caseInsensitive],
          range: searchStart..<range.upperBound)
      {
        if let lastActionEndIndex, found.upperBound <= lastActionEndIndex {
          searchStart = found.upperBound
          continue
        }
        if let currentBest = best {
          if found.lowerBound < currentBest.range.lowerBound
            || (found.lowerBound == currentBest.range.lowerBound
              && found.upperBound > currentBest.range.upperBound)
          {
            best = ActionKeywordMatch(keyword: keyword, range: found)
          }
        } else {
          best = ActionKeywordMatch(keyword: keyword, range: found)
        }
        break
      }
    }
    return best
  }

  private static func extractActionRange(
    in text: String,
    sentence: Substring,
    match: ActionKeywordMatch,
    minStart: String.Index
  ) -> Range<String.Index> {
    // Extend sentenceEnd across unpunctuated chunk splits if needed so actions near a chunk
    // boundary are never truncated either.
    var sentenceEnd = sentence.endIndex
    let lookaheadLimit =
      text.index(
        match.range.lowerBound, offsetBy: maxFragmentCharacters + maxChunkLookahead,
        limitedBy: text.endIndex)
      ?? text.endIndex
    while sentenceEnd < lookaheadLimit {
      if let scalar = text[sentenceEnd].unicodeScalars.first,
        sentenceDelimiters.contains(scalar)
      {
        break
      }
      sentenceEnd = text.index(after: sentenceEnd)
    }

    if text.distance(from: sentence.startIndex, to: sentenceEnd) <= maxFragmentCharacters {
      return sentence.startIndex..<sentenceEnd
    }

    var actionStart: String.Index
    if leadActionKeywords.contains(match.keyword) {
      actionStart = match.range.lowerBound
    } else {
      let leadMin =
        text.index(match.range.lowerBound, offsetBy: -24, limitedBy: minStart) ?? minStart
      actionStart = overlapStartIndex(
        in: text[sentence.startIndex..<sentenceEnd],
        before: match.range.lowerBound,
        minIndex: leadMin)
    }

    let rawEnd =
      text.index(actionStart, offsetBy: maxFragmentCharacters, limitedBy: sentenceEnd)
      ?? sentenceEnd
    var actionEnd = rawEnd
    if rawEnd < sentenceEnd {
      let minBreak =
        text.index(actionStart, offsetBy: maxFragmentCharacters / 2, limitedBy: rawEnd)
        ?? actionStart
      var probe = rawEnd
      while probe > minBreak {
        let previous = text.index(before: probe)
        if text[previous].isWhitespace {
          actionEnd = previous
          break
        }
        probe = previous
      }
    }

    // Ensure the extracted action has at least 12 characters when near the tail of the input.
    if text.distance(from: actionStart, to: actionEnd) < 12 {
      actionStart =
        text.index(actionEnd, offsetBy: -12, limitedBy: sentence.startIndex)
        ?? sentence.startIndex
    }
    return actionStart..<actionEnd
  }

  /// Carries trailing keyword context across unpunctuated fragment/chunk boundaries so multi-word
  /// phrases like "we should" or "action item" are never lost when split across a boundary.
  private static func overlapStartIndex(
    in slice: Substring, before splitIndex: String.Index, minIndex: String.Index
  ) -> String.Index {
    let clampedMin = max(slice.startIndex, minIndex)
    guard splitIndex > clampedMin else { return clampedMin }
    let rawOverlapStart =
      slice.index(splitIndex, offsetBy: -fragmentOverlapCharacters, limitedBy: clampedMin)
      ?? clampedMin
    let maxOverlapStart =
      slice.index(splitIndex, offsetBy: -(fragmentOverlapCharacters / 2), limitedBy: clampedMin)
      ?? clampedMin
    guard rawOverlapStart < maxOverlapStart else { return rawOverlapStart }
    var cursor = rawOverlapStart
    while cursor < maxOverlapStart {
      if slice[cursor].isWhitespace {
        var wordStart = slice.index(after: cursor)
        while wordStart < maxOverlapStart && slice[wordStart].isWhitespace {
          wordStart = slice.index(after: wordStart)
        }
        return wordStart
      }
      cursor = slice.index(after: cursor)
    }
    return rawOverlapStart
  }

  private static func scoreActionItem(lower: String) -> Double? {
    guard actionKeywords.contains(where: { lower.contains($0) }) else { return nil }
    var score = 1.0
    for keyword in highSignalActionKeywords where lower.contains(keyword) {
      score += 2.0
    }
    return score
  }

  private static func scoreSummarySentence(
    sentence: String, lower: String, index: Int
  ) -> Double {
    let wordCount = sentence.split(separator: " ").count
    var score = Double(min(wordCount, 24)) * 0.4
    if index == 0 { score += 3.0 }
    for keyword in priorityKeywords where lower.contains(keyword) {
      score += 2.5
    }
    for keyword in actionKeywords where lower.contains(keyword) {
      score += 1.5
    }
    return score
  }

  private static func insertAction(_ candidate: ScoredEntry, into actions: inout [ScoredEntry]) {
    guard
      !actions.contains(where: {
        $0.sourceStart == candidate.sourceStart || $0.text == candidate.text
      })
    else { return }
    if actions.count < maxActionItems {
      actions.append(candidate)
      return
    }
    // Prefer higher-signal or more recent action items when the cap is reached so late TODOs
    // at the end of a long transcript are never dropped.
    if let weakestIndex = actions.indices.min(by: { lhs, rhs in
      if actions[lhs].score != actions[rhs].score {
        return actions[lhs].score < actions[rhs].score
      }
      return actions[lhs].index < actions[rhs].index
    }),
      candidate.score >= actions[weakestIndex].score
    {
      actions[weakestIndex] = candidate
    }
  }

  private static func insertSummary(
    _ candidate: ScoredEntry, into sentences: inout [ScoredEntry]
  ) {
    guard !sentences.contains(where: { $0.text == candidate.text }) else { return }
    if sentences.count < maxSummarySentences {
      sentences.append(candidate)
      return
    }
    if let weakestIndex = sentences.indices.min(by: { lhs, rhs in
      if sentences[lhs].score != sentences[rhs].score {
        return sentences[lhs].score < sentences[rhs].score
      }
      return sentences[lhs].index > sentences[rhs].index
    }),
      candidate.score > sentences[weakestIndex].score
    {
      sentences[weakestIndex] = candidate
    }
  }
}
