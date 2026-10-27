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
