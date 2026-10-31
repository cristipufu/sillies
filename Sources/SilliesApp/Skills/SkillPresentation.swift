import SilliesCore

struct SkillPresentation: Sendable {
  let persistenceError: String?
  let completedRecord: SessionRecordHeader?
  let audioSession: AudioSessionPresentation?
}
