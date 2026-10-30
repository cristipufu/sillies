import SilliesCore
import Testing

@Test func recordSearchHonorsKindAndFindsAccentedTextInSessionContent() {
  var record = SessionRecord(
    kind: .listen, characterID: "mochi", characterName: "Mochi", appName: "Meeting")
  record.transcript = "Discuss the café launch"
  #expect(SessionRecordSearch(kind: .listen, query: "  CAFE  ").matches(record))
  #expect(!SessionRecordSearch(kind: .stash, query: "cafe").matches(record))
  #expect(SessionRecordSearch(kind: nil, query: "\n").matches(record))
  record.stashedItems = ["https://example.com/design"]
  #expect(SessionRecordSearch(kind: nil, query: "design").matches(record))
}
