import Foundation
import SilliesCore
import Testing

@Test func skillWheelHasFiveSeparatedTargets() {
  #expect(CompanionSkillKind.radialSkills == [.listen, .participate, .snap, .explain, .record])
  for direction in [RadialSkillMenuLayout.Direction.upward, .downward] {
    let items = RadialSkillMenuLayout.items(around: .zero, direction: direction)
    for (index, item) in items.enumerated() {
      for other in items.dropFirst(index + 1) {
        #expect(
          hypot(item.center.x - other.center.x, item.center.y - other.center.y)
            > RadialSkillMenuLayout.bubbleHitRadius * 2)
      }
    }
  }
}

@Test func meetingSuggestionsNeedEvidenceAndRespectQuietInterval() {
  var gate = MeetingSuggestionGate()
  let source = "We will send the proposal next week. Nobody has been assigned to review it."
  let first = MeetingSuggestion(
    question: "Who will review the proposal?", evidence: "Nobody has been assigned to review it.",
    elapsed: 60)
  let accepted = gate.accept(first, source: source)
  let duplicate = gate.accept(first, source: source)
  let ungrounded = gate.accept(
    MeetingSuggestion(question: "When?", evidence: "The source never said this.", elapsed: 120),
    source: source)
  let tooSoon = gate.accept(
    MeetingSuggestion(
      question: "Which day next week?", evidence: "We will send the proposal next week.",
      elapsed: 70), source: source)
  let later = gate.accept(
    MeetingSuggestion(
      question: "Which day next week?", evidence: "We will send the proposal next week.",
      elapsed: 120), source: source)
  #expect(accepted)
  #expect(!duplicate)
  #expect(!ungrounded)
  #expect(!tooSoon)
  #expect(later)
}

@Test func sessionPreservesSelectedLanguageForNotesAfterRelaunch() throws {
  let record = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Microphone")),
    metadata: .init(transcription: .init(languageIdentifier: "fr-FR")))
  let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
  #expect(decoded.languageIdentifier == "fr-FR")
}

@Test func meetingSuggestionsContinueAfterHistoryFillsAndFitTheSpeechBubble() {
  var gate = MeetingSuggestionGate()
  for index in 0..<20 {
    let evidence = "Unresolved topic number \(index) needs an owner."
    let suggestion = MeetingSuggestion(
      question: "Who owns topic \(index)?", evidence: evidence, elapsed: Double(index) * 60)
    let accepted = gate.accept(suggestion, source: evidence)
    #expect(accepted)
  }
  #expect(gate.suggestions.count == MeetingSuggestionGate.maximumSuggestions)
  #expect(gate.suggestions.last?.question == "Who owns topic 19?")
  let oversized = MeetingSuggestion(
    question: String(repeating: "a", count: MeetingSuggestionGate.maximumQuestionCharacters + 1),
    evidence: "An unresolved concern remains.", elapsed: 2000)
  let accepted = gate.accept(oversized, source: oversized.evidence)
  #expect(!accepted)
}
