import Foundation
import SilliesCore
import Testing

@Test func adjacentSpeechRangesSurviveFloatingPointRounding() {
  var timeline = TranscriptTimeline()
  timeline.receive(
    .init(source: "Meeting", range: 2.22..<(2.22 + 2.16), text: "First", isFinal: true))
  timeline.receive(
    .init(source: "Meeting", range: 4.38..<(4.38 + 3.0), text: "Next draft", isFinal: false))
  timeline.receive(
    .init(source: "Meeting", range: 4.38..<(4.38 + 3.0), text: "Next", isFinal: true))
  #expect(timeline.text == "[00:02] Meeting: First\n[00:04] Meeting: Next")
}

@Test func transcriptPreviewMatchesFullHistoryWithLateRevisionsAndLanguageMarkers() {
  var timeline = TranscriptTimeline()
  for index in 0..<600 {
    let start = Double(index) * 4
    timeline.receive(
      .init(
        source: "Meeting", range: start..<(start + 2), text: "Meeting words \(index)", isFinal: true
      ))
    timeline.receive(
      .init(
        source: "Microphone", range: (start + 1)..<(start + 3), text: "My draft \(index)",
        isFinal: false))
    if index.isMultiple(of: 100) { timeline.markLanguage("French", at: start + 3) }
  }
  timeline.receive(
    .init(source: "Microphone", range: 41..<43, text: "A late correction 🐈‍⬛", isFinal: true))
  for limit in [0, 1, 30, 8_192, 100_000] {
    #expect(timeline.preview(characterLimit: limit) == String(timeline.text.suffix(limit)))
  }
  let revision = timeline.revision
  timeline.receive(
    .init(source: "Microphone", range: 41..<43, text: "A stale revision", isFinal: false))
  #expect(timeline.revision == revision)
}

@Test func longSessionTranscriptPublicationStaysWithinItsWorkerBudget() {
  var timeline = TranscriptTimeline()
  let simulatedHours = 4
  let secondsPerHour = 3_600
  let secondsPerPassage = 2
  let draftTime = Double(simulatedHours * secondsPerHour)
  let passageCount = simulatedHours * secondsPerHour / secondsPerPassage
  for index in 0..<passageCount {
    let start = Double(index * secondsPerPassage)
    timeline.receive(
      .init(
        source: "Meeting", range: start..<(start + 1),
        text: "A saved meeting passage with its owner and deadline \(index).", isFinal: true))
  }
  var samples: [Duration] = []
  for index in 0..<50 {
    let start = ContinuousClock.now
    timeline.receive(
      .init(
        source: "Meeting", range: draftTime..<(draftTime + 1),
        text: "An updated live draft \(index)", isFinal: false))
    let preview = timeline.preview(characterLimit: 8_192)
    samples.append(ContinuousClock.now - start)
    #expect(preview.contains("An updated live draft \(index)"))
    #expect(preview.count == 8_192)
  }
  samples.sort()
  #expect(samples[47] < .milliseconds(4))
  #expect(timeline.text.contains("passage with its owner and deadline 0."))
}

@Test func singleMeetingStreamRevisionsKeepDisjointPhrasesAndStableOrder() {
  var timeline = TranscriptTimeline()
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "First draft", isFinal: false))
  timeline.receive(.init(source: "Meeting", range: 3..<5, text: "Second draft", isFinal: false))
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "First finished", isFinal: true))
  #expect(timeline.text == "[00:00] Meeting: First finished\n[00:03] Meeting: Second draft")
  timeline.receive(.init(source: "Meeting", range: 3..<5, text: "Second finished", isFinal: true))
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "First finished", isFinal: true))
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "Stale draft", isFinal: false))
  #expect(timeline.text == "[00:00] Meeting: First finished\n[00:03] Meeting: Second finished")
}

@Test func transcriptUsesSpeechTimeInsteadOfCompletionTimeAcrossSources() {
  var timeline = TranscriptTimeline()
  timeline.receive(.init(source: "Microphone", range: 5..<6, text: "Later words", isFinal: true))
  timeline.receive(.init(source: "Meeting", range: 1..<4, text: "Earlier words", isFinal: false))
  timeline.receive(
    .init(source: "Meeting", range: 1..<4, text: "Earlier corrected words", isFinal: true))
  #expect(
    timeline.text == "[00:01] Meeting: Earlier corrected words\n[00:05] Microphone: Later words")
}

@Test func finalizationWatermarkPreservesUnchangedEarlierResults() {
  var timeline = TranscriptTimeline()
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "Already spoken", isFinal: false))
  timeline.receive(
    .init(source: "Meeting", range: 3..<4, text: "New words", isFinal: false, finalizedThrough: 2))
  timeline.receive(.init(source: "Meeting", range: 0..<2, text: "Obsolete", isFinal: false))
  timeline.preservePending()
  timeline.markLanguage("French", at: 5)
  #expect(
    timeline.text
      == "[00:00] Meeting: Already spoken\n[00:03] Meeting: New words\n[00:05] Language: French")
}

@Test func transcriptPreviewIncludesTheBoundaryNewlineAndOrdersSimultaneousMarkers() {
  var timeline = TranscriptTimeline()
  timeline.markLanguage("English", at: 0)
  timeline.markLanguage("French", at: 0)
  timeline.receive(.init(source: "Meeting", range: 1..<2, text: "Last", isFinal: true))
  let lastLineCount = "[00:01] Meeting: Last".count
  for limit in [lastLineCount, lastLineCount + 1, lastLineCount + 2, 60] {
    #expect(timeline.preview(characterLimit: limit) == String(timeline.text.suffix(limit)))
  }
}

@Test func transcriptPreviewBoundsOversizedDraftsWithoutLosingSavedText() {
  var timeline = TranscriptTimeline()
  let draft = String(repeating: "A long uninterrupted passage 🐈‍⬛. ", count: 10_000)
  timeline.receive(.init(source: "Meeting", range: 0..<600, text: draft, isFinal: false))
  timeline.receive(.init(source: "Microphone", range: 601..<602, text: "Later", isFinal: true))
  for limit in [1, 8, 8_192] {
    #expect(timeline.preview(characterLimit: limit) == String(timeline.text.suffix(limit)))
  }
  #expect(timeline.text.contains(draft.trimmingCharacters(in: .whitespacesAndNewlines)))
}
