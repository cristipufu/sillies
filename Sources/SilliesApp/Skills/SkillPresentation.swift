import SilliesCore

struct SkillPresentation: Sendable {
  let persistenceError: String?
  let completedRecord: SessionRecord?
  let audioSession: AudioSessionPresentation?
}
