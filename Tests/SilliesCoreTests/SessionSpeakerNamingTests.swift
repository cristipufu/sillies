import SilliesCore
import Testing

@Test func speakerNamesAreScopedToTheirSourceAndPreserveSpokenWords() {
  let original = """
    [00:01] Meeting · Speaker 1: Speaker 1 said ship API_v2.
    [00:02] Microphone · Speaker 1: Ștefan will review it.
    [00:03] Meeting · Speakers 1 + 2 · overlap: We agree.
    [00:04] Language: Romanian
    """
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: original)))
  let speakers = SessionSpeakerNaming.speakers(in: record)
  #expect(speakers.count == 3)
  let named = SessionSpeakerNaming.rename(speakers[0], to: "Alex", in: record)
  #expect(named.transcript.contains("Meeting · Alex: Speaker 1 said ship API_v2."))
  #expect(named.transcript.contains("Microphone · Speaker 1: Ștefan"))
  #expect(named.transcript.contains("Meeting · Alex + Speaker 2 · overlap"))
  #expect(named.transcript.contains("[00:04] Language: Romanian"))
  let renamed = SessionSpeakerNaming.rename(speakers[0], to: "Ana", in: named)
  #expect(renamed.transcript.contains("Meeting · Ana:"))
  #expect(renamed.originalSpeakerTranscript == original)
  #expect(SessionSpeakerNaming.rename(speakers[0], to: "", in: renamed).transcript == original)
}

@Test func vaultRetentionKeepsEverythingByDefaultAndProtectsImportantRecords() {
  let records = (0..<205).map { number in
    var record = SessionRecord(
      kind: number == 0 ? .stash : .record,
      origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")))
    record.isProtected = number == 1
    return record
  }
  #expect(VaultRetentionPolicy.keepAll.expired(in: records).isEmpty)
  let expired = VaultRetentionPolicy.recent200.expired(in: records)
  #expect(expired.count == 3)
  #expect(expired.allSatisfy { !$0.isProtected && $0.kind != .stash })
}
