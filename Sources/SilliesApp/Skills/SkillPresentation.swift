import SilliesChat
import SilliesCore

struct SkillPresentation: Sendable {
  let persistenceError: String?
  let completedRecord: SessionRecordHeader?
  let audioSession: AudioSessionPresentation?
  var conversation: ChatSession? = nil
  var speakingLevel: Double = 0
}
