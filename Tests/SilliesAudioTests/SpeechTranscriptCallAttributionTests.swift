import Foundation
import SilliesCore
import SilliesSpeech
import Testing

@testable import SilliesAudio

@Test func speechTranscriptUsesWordTimingsAndSeparatesLocalIdentity() throws {
  let alice = try #require(CallSpeakerName(rawValue: "Alice"))
  let bob = try #require(CallSpeakerName(rawValue: "Bob"))
  let pat = try #require(CallSpeakerName(rawValue: "Pat"))
  var names = CallSpeakerTimeline()
  for step in 0...24 {
    let time = Double(step) / 2
    names.append(
      .init(
        source: .init(processID: 42, windowID: 7), capturedAt: time,
        availability: .available, speaking: [time < 5 ? alice : bob],
        participants: [alice, bob, pat], localParticipant: pat), at: time)
  }
  var transcript = SpeechTranscript()
  var remote = SpeechPhrase(
    text: "First transition last.", isFinal: true, startTime: 0, duration: 10)
  remote.words = [
    .init(text: "First", start: 2, end: 3),
    .init(text: "transition", start: 4.8, end: 5.2),
    .init(text: "last.", start: 7, end: 8),
  ]
  transcript.receive(remote, source: .application, elapsed: 10)
  transcript.receive(
    .init(text: "My words.", isFinal: true, startTime: 6, duration: 0.5), source: .microphone,
    elapsed: 10)
  let original = transcript.originalText
  let preview = transcript.preview
  transcript.attributeCallSpeakers(using: names)
  #expect(transcript.segments.map(\.automaticSpeakerName) == [alice, nil, pat, bob])
  #expect(transcript.originalText == original)
  #expect(transcript.preview != preview)
  #expect(transcript.preview == transcript.text)
}

@Test func speechTranscriptPreservesPendingWordsWhenCaptureFinishes() throws {
  var transcript = SpeechTranscript()
  var draft = SpeechPhrase(text: "Unfinished speech.", isFinal: false, startTime: 1, duration: 2)
  draft.words = [
    .init(text: "Unfinished", start: 1, end: 2), .init(text: "speech.", start: 2, end: 3),
  ]
  transcript.receive(draft, source: .application, elapsed: 3)
  transcript.preserveDrafts()
  transcript.attributeCallSpeakers(using: CallSpeakerTimeline())
  #expect(transcript.segments.map(\.text) == ["Unfinished speech."])
  #expect(transcript.segments.first?.automaticSpeakerName == nil)
}
