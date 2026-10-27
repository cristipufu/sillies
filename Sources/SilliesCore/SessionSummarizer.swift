import Foundation

/// Deterministic on-device summarizer and action-item extractor for transcripts and OCR captures.
/// Processes arbitrarily long transcripts in bounded chunks so late action items are never dropped.
public enum SessionSummarizer: Sendable {
  private static let maxSummarySentences = 3
  private static let maxActionItems = 5
  private static let minFragmentCharacterCount = 12
  private static let shortFallbackCharacterLimit = 180
  private static let summaryFallbackCharacterLimit = 200
  private static let maxScoredWordCount = 24
  private static let actionLeadContextOffset = 24
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

  private struct ExtractionState {
    var topSentences: [ScoredEntry] = []
    var topActions: [ScoredEntry] = []
    var sentenceIndex = 0
    var lastActionEndIndex: String.Index?
  }

  public static func summarize(text: String, fallbackContext: String) -> (
    summary: String, actionItems: [String]
  ) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      return (fallbackContext, [])
    }

    let state = collectScoredFragmentsAndActions(in: cleaned)
    guard state.sentenceIndex > 0 || !state.topActions.isEmpty else {
      return (String(cleaned.prefix(shortFallbackCharacterLimit)), [])
    }

    let summary = formatSummary(from: state.topSentences, fallbackText: cleaned)
    let orderedActions = formatActions(from: state.topActions)
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

  private static func collectScoredFragmentsAndActions(in text: String) -> ExtractionState {
    var state = ExtractionState()
    forEachChunk(in: text) { chunk in
      forEachSentenceSlice(in: chunk) { sentence in
        forEachBoundedFragment(in: sentence) { fragment, detectionRange in
          processFragment(
            fragment,
            sentence: sentence,
            detectionRange: detectionRange,
            in: text,
            state: &state)
        }
      }
    }
    return state
  }

  private static func processFragment(
    _ fragment: Substring,
    sentence: Substring,
    detectionRange: Range<String.Index>,
    in text: String,
    state: inout ExtractionState
  ) {
    let currentIndex = state.sentenceIndex
    let fragmentText = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    if fragmentText.count >= minFragmentCharacterCount {
      state.sentenceIndex += 1
      let summaryText = String(fragmentText.prefix(maxFragmentCharacters))
      let summaryScore = scoreSummarySentence(
        sentence: summaryText, lower: summaryText.lowercased(), index: currentIndex)
      insertSummary(
        ScoredEntry(
          index: currentIndex,
          sourceStart: fragment.startIndex,
          score: summaryScore,
          text: summaryText),
        into: &state.topSentences)
    }

    extractActions(
      in: text,
      sentence: sentence,
      detectionRange: detectionRange,
      currentIndex: currentIndex,
      state: &state)
  }

  private static func extractActions(
    in text: String,
    sentence: Substring,
    detectionRange: Range<String.Index>,
    currentIndex: Int,
    state: inout ExtractionState
  ) {
    while let match = findFirstActionMatch(
      in: text, range: detectionRange, after: state.lastActionEndIndex)
    {
      let actionRange = extractActionRange(
        in: text,
        sentence: sentence,
        match: match,
        minStart: detectionRange.lowerBound)
      state.lastActionEndIndex = actionRange.upperBound
      let actionText = String(
        text[actionRange]
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(maxFragmentCharacters))
      guard actionText.count >= minFragmentCharacterCount,
        let actionScore = scoreActionItem(lower: actionText.lowercased())
      else { continue }
      insertAction(
        ScoredEntry(
          index: currentIndex,
          sourceStart: actionRange.lowerBound,
          score: actionScore,
          text: actionText),
        into: &state.topActions)
    }
  }

  private static func formatSummary(from entries: [ScoredEntry], fallbackText: String) -> String {
    let orderedSummary =
      entries
      .sorted { $0.index < $1.index }
      .map { String($0.text.prefix(maxFragmentCharacters)) }
    let joinedSummary =
      orderedSummary.isEmpty
      ? String(fallbackText.prefix(summaryFallbackCharacterLimit))
      : orderedSummary.map { "• \($0)" }.joined(separator: "\n")
    return String(joinedSummary.prefix(maxSummaryCharacters))
  }

  private static func formatActions(from entries: [ScoredEntry]) -> [String] {
    entries
      .sorted { $0.sourceStart < $1.sourceStart }
      .map { String($0.text.prefix(maxFragmentCharacters)) }
  }

  private static func forEachChunk(in text: String, body: (Substring) -> Void) {
    var start = text.startIndex
    while start < text.endIndex {
      let targetEnd =
        text.index(start, offsetBy: chunkCharacterSize, limitedBy: text.endIndex)
        ?? text.endIndex
      let (end, splitAtDelimiter) = resolveChunkEnd(in: text, from: targetEnd)
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

  private static func resolveChunkEnd(
    in text: String, from targetEnd: String.Index
  ) -> (end: String.Index, splitAtDelimiter: Bool) {
    guard targetEnd < text.endIndex else { return (targetEnd, false) }
    let lookaheadLimit =
      text.index(targetEnd, offsetBy: maxChunkLookahead, limitedBy: text.endIndex)
      ?? text.endIndex
    var cursor = targetEnd
    var whitespaceSplit: String.Index?
    while cursor < lookaheadLimit {
      if let scalar = text[cursor].unicodeScalars.first {
        if sentenceDelimiters.contains(scalar) {
          return (text.index(after: cursor), true)
        }
        if whitespaceSplit == nil && CharacterSet.whitespaces.contains(scalar) {
          whitespaceSplit = text.index(after: cursor)
        }
      }
      cursor = text.index(after: cursor)
    }
    return (whitespaceSplit ?? targetEnd, false)
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

      let splitIndex = resolveWordBoundaryEnd(in: raw, from: sliceStart, rawEnd: windowEnd)
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
    let sentenceEnd = extendSentenceEndAcrossChunkSplit(
      in: text, sentenceEnd: sentence.endIndex, from: match.range.lowerBound)
    if text.distance(from: sentence.startIndex, to: sentenceEnd) <= maxFragmentCharacters {
      return sentence.startIndex..<sentenceEnd
    }

    var actionStart = resolveActionStartIndex(
      in: text,
      sentenceStart: sentence.startIndex,
      sentenceEnd: sentenceEnd,
      match: match,
      minStart: minStart)
    let rawEnd =
      text.index(actionStart, offsetBy: maxFragmentCharacters, limitedBy: sentenceEnd)
      ?? sentenceEnd
    let actionEnd =
      rawEnd < sentenceEnd
      ? resolveWordBoundaryEnd(in: text[...], from: actionStart, rawEnd: rawEnd)
      : rawEnd

    if text.distance(from: actionStart, to: actionEnd) < minFragmentCharacterCount {
      actionStart =
        text.index(actionEnd, offsetBy: -minFragmentCharacterCount, limitedBy: sentence.startIndex)
        ?? sentence.startIndex
    }
    return actionStart..<actionEnd
  }

  /// Extends `sentenceEnd` across unpunctuated chunk splits so actions near a chunk boundary
  /// are never truncated.
  private static func extendSentenceEndAcrossChunkSplit(
    in text: String,
    sentenceEnd: String.Index,
    from matchStart: String.Index
  ) -> String.Index {
    var cursor = sentenceEnd
    let lookaheadLimit =
      text.index(
        matchStart, offsetBy: maxFragmentCharacters + maxChunkLookahead,
        limitedBy: text.endIndex)
      ?? text.endIndex
    while cursor < lookaheadLimit {
      if let scalar = text[cursor].unicodeScalars.first,
        sentenceDelimiters.contains(scalar)
      {
        break
      }
      cursor = text.index(after: cursor)
    }
    return cursor
  }

  private static func resolveActionStartIndex(
    in text: String,
    sentenceStart: String.Index,
    sentenceEnd: String.Index,
    match: ActionKeywordMatch,
    minStart: String.Index
  ) -> String.Index {
    if leadActionKeywords.contains(match.keyword) {
      return match.range.lowerBound
    }
    let leadMin =
      text.index(match.range.lowerBound, offsetBy: -actionLeadContextOffset, limitedBy: minStart)
      ?? minStart
    return overlapStartIndex(
      in: text[sentenceStart..<sentenceEnd],
      before: match.range.lowerBound,
      minIndex: leadMin)
  }

  private static func resolveWordBoundaryEnd(
    in slice: Substring, from start: String.Index, rawEnd: String.Index
  ) -> String.Index {
    let minBreak =
      slice.index(start, offsetBy: maxFragmentCharacters / 2, limitedBy: rawEnd) ?? start
    var probe = rawEnd
    while probe > minBreak {
      let previous = slice.index(before: probe)
      if slice[previous].isWhitespace {
        return previous
      }
      probe = previous
    }
    return rawEnd
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
    var score = Double(min(wordCount, maxScoredWordCount)) * 0.4
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
