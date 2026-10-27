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

@Test func legacyRecordsDecodeWithoutNewAudioAndExplanationFields() throws {
  let record = SessionRecord(
    kind: .watch, characterID: "mochi", characterName: "Mochi", appName: "Notes",
    summary: "Legacy record")
  let encoded = try JSONEncoder().encode(record)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  for key in [
    "audioFilename", "explanation", "processingNote", "suggestions", "languageIdentifier",
  ] {
    object.removeValue(forKey: key)
  }
  let oldData = try JSONSerialization.data(withJSONObject: object)
  let decoded = try JSONDecoder().decode(SessionRecord.self, from: oldData)
  #expect(decoded.kind == .watch)
  #expect(decoded.audioFilename == nil)
  #expect(decoded.suggestions.isEmpty)
  #expect(decoded.explanation.isEmpty)
  #expect(decoded.languageIdentifier == nil)
}

@Test func sessionPreservesSelectedLanguageForNotesAfterRelaunch() throws {
  let record = SessionRecord(
    kind: .record, characterID: "mochi", characterName: "Mochi", appName: "Microphone",
    languageIdentifier: "fr-FR")
  let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
  #expect(decoded.languageIdentifier == "fr-FR")
}
