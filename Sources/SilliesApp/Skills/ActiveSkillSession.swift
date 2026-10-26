import CoreGraphics
import Foundation
import SilliesCore

struct SkillCompletionOutcome {
  let record: SessionRecord
  let image: CGImage?
  let bannerSummary: String
}

enum SkillTickDisposition {
  case keepRunning(statusDetail: String, audioLevel: Double = 0)
  case completeNow
}

@MainActor
protocol ActiveSkillSession: AnyObject {
  var initialStatusDetail: String { get }
  func start()
  func tick(
    now: TimeInterval,
    startedAt: TimeInterval,
    currentDetail: String,
    currentAudioLevel: Double,
    target: WindowTargetCandidate,
    snapshot: WindowTargetSnapshot?,
    frontmostPID: pid_t?
  ) -> SkillTickDisposition
  func finalize(
    now: TimeInterval,
    startedAt: TimeInterval,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate
  ) -> SkillCompletionOutcome?
  func cancel()
}
