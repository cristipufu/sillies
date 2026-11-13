import SilliesCore

actor SessionSpeakerWorker {
  func speakers(in record: SessionRecord) -> [SessionSpeakerIdentity] {
    SessionSpeakerNaming.speakers(in: record)
  }
  func rename(_ speaker: SessionSpeakerIdentity, to name: String, in record: SessionRecord)
    throws -> SessionRecord
  {
    try SessionSpeakerNaming.rename(speaker, to: name, in: record)
  }
}
