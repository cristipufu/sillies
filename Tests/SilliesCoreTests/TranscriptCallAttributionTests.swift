import Foundation
import SilliesCore
import Testing

private let remoteSource = "Meeting"
private let localSource = "Microphone"
private let observationSource = CallSpeakerObservation.Source(processID: 42, windowID: 7)
private let firstPerson = CallSpeakerName(rawValue: "Alice")!
private let secondPerson = CallSpeakerName(rawValue: "Bob")!
private let localPerson = CallSpeakerName(rawValue: "Pat")!

private func evidence(through end: Int = 24) -> CallSpeakerTimeline {
  var timeline = CallSpeakerTimeline()
  for step in 0...end {
    let time = Double(step) / 2
    timeline.append(
      .init(
        source: observationSource, capturedAt: time, availability: .available,
        speaking: [time < 5 ? firstPerson : secondPerson],
        participants: [localPerson, firstPerson, secondPerson], localParticipant: localPerson),
      at: time)
  }
  return timeline
}

private let changingWords: [TranscriptWord] = [
  .init(text: "First", start: 2, end: 3),
  .init(text: "uncertain", start: 4.8, end: 5.2),
  .init(text: "last.", start: 7, end: 8),
]

private func passage(words: [TranscriptWord] = changingWords) -> TranscriptTimeline.Passage {
  .init(
    source: remoteSource, range: 0..<10, text: TranscriptWord.renderedText(words), isFinal: true,
    speaker: .identified(1), words: words)
}

@Test func callAttributionSplitsOnlyAtWordBoundariesAndPreservesOriginalTranscript() {
  var transcript = TranscriptTimeline()
  transcript.receive(passage())
  transcript.receive(.init(source: localSource, range: 6..<6.5, text: "Local.", isFinal: true))
  let original = transcript.text
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.map(\.text) == ["First", "uncertain", "Local.", "last."])
  #expect(transcript.segments.map(\.automaticSpeakerName) == [firstPerson, nil, nil, secondPerson])
  #expect(
    transcript.segments.filter { $0.source == remoteSource }.allSatisfy {
      $0.speaker == .identified(1)
    })
  #expect(Set(transcript.segments.map(\.id)).count == transcript.segments.count)
  #expect(transcript.originalText == original)
  #expect(
    transcript.text
      == "[00:02] Meeting · Alice: First\n[00:05] Meeting · Speaker 1: uncertain\n[00:06] Microphone: Local.\n[00:07] Meeting · Bob: last."
  )
  for limit in [1, 20, 80, 8192] {
    #expect(transcript.preview(characterLimit: limit) == String(transcript.text.suffix(limit)))
  }
  let segments = transcript.segments
  let revision = transcript.revision
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  transcript.receive(.init(source: remoteSource, range: 0..<10, text: "Late draft", isFinal: false))
  #expect(transcript.segments == segments)
  #expect(transcript.revision == revision)
}

@Test func callAttributionWaitsForEvidenceWithoutFreezingTheFinalDraft() {
  var transcript = TranscriptTimeline()
  var draft = passage()
  transcript.receive(
    .init(source: draft.source, range: draft.range, text: draft.text, isFinal: false))
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.count == 1)
  // The final result has the same text/range as the draft, but adds word timing metadata.
  draft.words = changingWords
  transcript.receive(draft)
  transcript.attributeCallSpeakers(using: evidence(through: 12), source: remoteSource)
  #expect(transcript.segments.count == 1)
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.count == 3)
}

@Test func callAttributionKeepsAttachedSubwordsTogether() {
  let words: [TranscriptWord] = [
    .init(text: "First", start: 2, end: 3),
    .init(text: "uncer", start: 4.6, end: 4.9),
    .init(text: "tain", start: 4.9, end: 5.2, boundary: .attached),
    .init(text: "!", start: 5.2, end: 5.2, boundary: .attached),
    .init(text: "last.", start: 7, end: 8),
  ]
  var transcript = TranscriptTimeline()
  transcript.receive(passage(words: words))
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.map(\.text) == ["First", "uncertain!", "last."])
  #expect(transcript.segments.map(\.automaticSpeakerName) == [firstPerson, nil, secondPerson])
}

@Test func callAttributionNeverReconstructsCorrectedOrInvalidlyTimedWords() {
  let invalidWords: [[TranscriptWord]] = [
    [],
    [.init(text: "First uncertain last.", start: .nan, end: 8)],
    [.init(text: "First", start: 2, end: 4), .init(text: "uncertain last.", start: 3, end: 8)],
    [.init(text: "First uncertain last.", start: 2, end: 11)],
    [.init(text: "Wrong words", start: 2, end: 8)],
  ]
  for words in invalidWords {
    var transcript = TranscriptTimeline()
    transcript.receive(
      .init(
        source: remoteSource, range: 0..<10, text: "First uncertain last.", isFinal: true,
        words: words))
    transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
    #expect(transcript.segments.count == 1)
    #expect(transcript.segments.first?.text == "First uncertain last.")
    #expect(transcript.segments.first?.automaticSpeakerName == nil)
  }
}

@Test func callAttributionPreservesAcousticOverlapDespiteClearVisualEvidence() {
  var transcript = TranscriptTimeline()
  var phrase = passage()
  phrase.speaker = .overlapping([1, 2])
  transcript.receive(phrase)
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.count == 1)
  #expect(transcript.segments.first?.automaticSpeakerName == nil)
  #expect(transcript.segments.first?.speaker == .overlapping([1, 2]))
}

@Test func localCallIdentityRequiresFreshVerifiedParticipantEvidence() {
  let valid = evidence()
  #expect(valid.decision(for: 2..<8, participant: .local) == .resolved(localPerson))
  var transcript = TranscriptTimeline()
  transcript.receive(.init(source: localSource, range: 2..<8, text: "My words", isFinal: true))
  transcript.attributeCallSpeakers(using: valid, source: localSource, participant: .local)
  #expect(transcript.segments.first?.automaticSpeakerName == localPerson)
  #expect(transcript.text == "[00:02] Microphone · Pat: My words")

  var unverified = CallSpeakerTimeline()
  var interrupted = CallSpeakerTimeline()
  var conflicting = CallSpeakerTimeline()
  for step in 0...20 {
    let time = Double(step) / 2
    unverified.append(
      .init(
        source: observationSource, capturedAt: time, availability: .available,
        participants: [firstPerson], localParticipant: localPerson), at: time)
    interrupted.append(
      .init(
        source: observationSource, capturedAt: time,
        availability: time == 3 ? .unavailable : .available,
        participants: [localPerson], localParticipant: localPerson), at: time)
    conflicting.append(
      .init(
        source: observationSource, capturedAt: time, availability: .available,
        participants: [localPerson, firstPerson],
        localParticipant: time < 3 ? localPerson : firstPerson), at: time)
  }
  for timeline in [unverified, interrupted, conflicting] {
    #expect(timeline.decision(for: 2..<4, participant: .local) == .resolved(nil))
  }
}

@Test func timedAttributionExpiresWithoutRewritingArchivedPassages() {
  var transcript = TranscriptTimeline()
  transcript.receive(passage())
  transcript.receive(.init(source: remoteSource, range: 200..<201, text: "Later", isFinal: true))
  transcript.attributeCallSpeakers(using: evidence(), source: remoteSource)
  #expect(transcript.segments.count == 2)
  #expect(transcript.segments.allSatisfy { $0.automaticSpeakerName == nil })
}
