import Foundation
import Testing

@testable import SilliesCore

private let callSource = CallSpeakerObservation.Source(processID: 42, windowID: 7)
private func callName(_ text: String) -> CallSpeakerName { CallSpeakerName(rawValue: text)! }
private func reading(
  _ time: Double, speaking: [String], roster: CallSpeakerObservation.Roster = .partial,
  participants: [String] = ["Me", "Alice", "Bob"], local: String? = "Me"
) -> CallSpeakerObservation {
  .init(
    source: callSource, capturedAt: time, availability: .available,
    speaking: speaking.map(callName), participants: participants.map(callName),
    localParticipant: local.map(callName), roster: roster)
}
private func timeline(_ speaking: (Double) -> [String]) -> CallSpeakerTimeline {
  var result = CallSpeakerTimeline()
  for step in 0...20 {
    let time = Double(step) / 2
    result.append(reading(time, speaking: speaking(time)), at: time)
  }
  return result
}
@Test func callSpeakerNamesRequireStableFreshEvidenceAndPreserveWords() throws {
  let names = timeline { _ in ["Alice"] }
  #expect(names.decision(for: 2..<4) == .resolved(callName("Alice")))
  var transcript = TranscriptTimeline()
  transcript.receive(
    .init(
      source: "Application", range: 2..<4, text: "Original words.", isFinal: true,
      speaker: .identified(1)))
  transcript.receive(.init(source: "Microphone", range: 2..<4, text: "My words.", isFinal: true))
  let original = transcript.text
  transcript.attributeCallSpeakers(using: names, source: "Application")
  #expect(transcript.text.contains("Application · Alice: Original words."))
  #expect(transcript.originalText == original)
  #expect(transcript.segments.first?.speaker == .identified(1))
  #expect(transcript.segments.first?.text == "Original words.")
  #expect(transcript.segments.last?.automaticSpeakerName == nil)
  let encoded = try JSONEncoder().encode(transcript.segments)
  #expect(try JSONDecoder().decode([TranscriptSegment].self, from: encoded) == transcript.segments)
}
@Test func callSpeakerTransitionsOverlapAndMissingEvidenceRemainAnonymous() {
  #expect(timeline { $0 < 3 ? ["Alice"] : ["Bob"] }.decision(for: 2..<4) == .resolved(nil))
  #expect(timeline { _ in ["Alice", "Bob"] }.decision(for: 2..<4) == .resolved(nil))
  #expect(timeline { _ in ["Me"] }.decision(for: 2..<4) == .resolved(nil))
  var names = CallSpeakerTimeline()
  names.append(reading(0, speaking: ["Alice"]), at: 0)
  #expect(names.decision(for: 2..<4) == .pending)
  names.append(.init(source: callSource, capturedAt: 8, availability: .unavailable), at: 8)
  #expect(names.decision(for: 2..<4) == .resolved(nil))
  let acceptedOld = names.append(reading(1, speaking: ["Bob"]), at: 1)
  #expect(!acceptedOld)
  let acceptedInvalid = names.append(reading(.nan, speaking: []), at: .nan)
  #expect(!acceptedInvalid)
}
@Test func callSpeakerPairFallbackRequiresACompleteRosterAndKnownLocalPerson() {
  var complete = CallSpeakerTimeline()
  var partial = CallSpeakerTimeline()
  var unknownSelf = CallSpeakerTimeline()
  for step in 0...20 {
    let time = Double(step) / 2
    complete.append(
      reading(time, speaking: [], roster: .complete, participants: ["Me", "Alice"]), at: time)
    partial.append(reading(time, speaking: [], participants: ["Me", "Alice"]), at: time)
    unknownSelf.append(
      reading(time, speaking: [], roster: .complete, participants: ["Me", "Alice"], local: nil),
      at: time)
  }
  #expect(complete.decision(for: 2..<4) == .resolved(callName("Alice")))
  #expect(partial.decision(for: 2..<4) == .resolved(nil))
  #expect(unknownSelf.decision(for: 2..<4) == .resolved(nil))
}
@Test func callSpeakerEvidenceIsBoundedAndCannotNameDiarizationOverlap() {
  var names = CallSpeakerTimeline()
  for step in 0...(CallSpeakerTimeline.maximumSamples + 10) {
    let time = Double(step) / 100
    names.append(reading(time, speaking: ["Alice"]), at: time)
  }
  #expect(names.sampleCount == CallSpeakerTimeline.maximumSamples)
  var transcript = TranscriptTimeline()
  transcript.receive(
    .init(
      source: "Application", range: 2..<4, text: "Two people.", isFinal: true,
      speaker: .overlapping([1, 2])))
  transcript.attributeCallSpeakers(using: names, source: "Application")
  #expect(transcript.segments.first?.automaticSpeakerName == nil)
}
@Test func callSpeakerNamesRejectUnsafeSavedLabels() throws {
  let expandingCluster = "A" + String(repeating: "\u{0344}", count: 5)
  let normalizationExpansion = String(repeating: expandingCluster, count: 64)
  for name in [
    "", "\n", "Alice\n[00:01] forged",
    String(repeating: "x", count: CallSpeakerName.maximumCharacters + 1),
    "A" + String(repeating: "\u{0301}", count: CallSpeakerName.maximumUTF8Bytes),
    normalizationExpansion,
  ] {
    #expect(CallSpeakerName(rawValue: name) == nil)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(CallSpeakerName.self, from: JSONEncoder().encode(name))
    }
  }
}

@Test func callSpeakerCorrectionsPreserveEditedWordsAndCanSuppressAutomaticNames() throws {
  let segment = TranscriptSegment(
    sequence: 0, source: "Application", start: 1, end: 2, text: "Original words.",
    speaker: .identified(1),
    automaticSpeakerName: callName("Alice"))
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Zoom")))
  record.transcriptSegments = [segment]
  record.transcript = segment.transcriptLine.replacingOccurrences(
    of: "Original words.", with: "Corrected words: keep Alice.")
  record.originalSpeakerTranscript = segment.originalTranscriptLine
  let identity = try #require(SessionSpeakerNaming.speakers(in: record).first)
  #expect(SessionSpeakerNaming.name(for: identity, in: record) == "Alice")
  let renamed = try SessionSpeakerNaming.rename(identity, to: "Dana", in: record)
  #expect(renamed.transcript == "[00:01] Application · Dana: Corrected words: keep Alice.")
  let cleared = try SessionSpeakerNaming.rename(identity, to: "", in: renamed)
  #expect(cleared.transcript == "[00:01] Application · Speaker 1: Corrected words: keep Alice.")
  #expect(SessionSpeakerNaming.name(for: identity, in: cleared).isEmpty)
  #expect(cleared.transcriptSegments == [segment])
  #expect(cleared.originalSpeakerTranscript == segment.originalTranscriptLine)
  #expect(
    try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(cleared)) == cleared)
  let restored = try SessionSpeakerNaming.rename(identity, to: "Alice", in: cleared)
  #expect(restored.transcript == record.transcript)
  #expect(restored.speakerNameSuppressions.isEmpty)
  let denseUnicode = String(repeating: "A" + String(repeating: "\u{0344}", count: 5), count: 80)
  let bounded = try SessionSpeakerNaming.rename(identity, to: denseUnicode, in: record)
  let savedName = try #require(bounded.speakerNames[identity.id])
  #expect(savedName.utf8.count <= CallSpeakerName.maximumUTF8Bytes)
  #expect(CallSpeakerName(rawValue: savedName) != nil)
  #expect(bounded.transcript.contains("Corrected words: keep Alice."))
}

@Test func callSpeakerCorrectionsWorkWithoutVoiceClusteringAndAvoidAmbiguousHeaders() throws {
  let first = TranscriptSegment(
    sequence: 0, source: "Application", start: 1, end: 1.2,
    text: "A", speaker: .identified(1), automaticSpeakerName: callName("Alice"))
  let second = TranscriptSegment(
    sequence: 1, source: "Application", start: 1.3, end: 1.4,
    text: "B", speaker: .identified(2), automaticSpeakerName: callName("Alice"))
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Zoom")))
  record.transcriptSegments = [first, second]
  record.transcript = record.transcriptSegments.map(\.transcriptLine).joined(separator: "\n")
  let identities = SessionSpeakerNaming.speakers(in: record)
  let ambiguousIdentity = try #require(identities.first)
  #expect(throws: SessionSpeakerNaming.Failure.ambiguousHeaders) {
    try SessionSpeakerNaming.rename(ambiguousIdentity, to: "Dana", in: record)
  }
  let unclustered = TranscriptSegment(
    sequence: 0, source: "Application", start: 1, end: 2,
    text: "Keep this", speaker: nil, automaticSpeakerName: callName("Alice"))
  record.transcriptSegments = [unclustered]
  record.transcript = unclustered.transcriptLine
  let participant = try #require(SessionSpeakerNaming.speakers(in: record).first)
  let cleared = try SessionSpeakerNaming.rename(participant, to: "", in: record)
  #expect(cleared.transcript == "[00:01] Application: Keep this")
  #expect(
    try SessionSpeakerNaming.rename(participant, to: "Dana: Z", in: cleared).transcript
      == "[00:01] Application · Dana： Z: Keep this")
}

@Test func callSpeakerPollingWaitsForWindowSettlementAndBoundsRequests() {
  var polling = CallSpeakerPolling()
  let frame = CGRect(x: 0, y: 0, width: 600, height: 400)
  let initial = polling.isSettled(frame: frame, at: 0)
  #expect(!initial)
  let settled = polling.isSettled(frame: frame, at: 0.6)
  #expect(settled)
  let first = polling.takeRead(at: 0.6)
  let tooSoon = polling.takeRead(at: 0.7)
  let next = polling.takeRead(at: 1.1)
  #expect(first && !tooSoon && next)
  let moving = polling.isSettled(frame: frame.offsetBy(dx: 1, dy: 0), at: 1.2)
  #expect(!moving)
  polling.suspend()
  let restarted = polling.isSettled(frame: frame, at: 10)
  #expect(!restarted)
}
