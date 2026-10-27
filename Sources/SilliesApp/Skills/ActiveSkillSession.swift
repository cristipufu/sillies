import CoreGraphics
import Foundation
import SilliesCore

struct SkillCompletionOutcome: Sendable {
  let record: SessionRecord
  let image: CGImage?
  var pngData: Data? = nil
  let bannerSummary: String
}

enum SkillTickDisposition {
  case keepRunning(statusDetail: String, audioLevel: Double = 0)
  case completeNow
}

struct SkillTickContext {
  let now: TimeInterval
  let startedAt: TimeInterval
  let currentDetail: String
  let currentAudioLevel: Double
  let target: WindowTargetCandidate?
  let snapshot: WindowTargetSnapshot?
  let frontmostPID: pid_t?
}

struct SkillFinalizeContext: Sendable {
  let now: TimeInterval
  let startedAt: TimeInterval
  let companionID: String
  let companionName: String
  let target: WindowTargetCandidate?
}

@MainActor
protocol ActiveSkillSession: AnyObject {
  var initialStatusDetail: String { get }
  func start()
  func tick(_ context: SkillTickContext) -> SkillTickDisposition
  func finish(
    _ context: SkillFinalizeContext,
    completion: @escaping @MainActor (SkillCompletionOutcome?) -> Void)
  func cancel()
}
