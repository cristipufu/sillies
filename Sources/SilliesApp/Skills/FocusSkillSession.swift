import Foundation
import SilliesCore

@MainActor
final class FocusSkillSession: ActiveSkillSession {
  static let sprintDuration: TimeInterval = 25 * 60
  static let distractionThresholdSeconds: TimeInterval = 25

  let target: WindowTargetCandidate
  private var lastTickAt: TimeInterval
  private var focusedSeconds: Double = 0
  private var awaySince: TimeInterval?

  init(target: WindowTargetCandidate, startedAt: TimeInterval) {
    self.target = target
    self.lastTickAt = startedAt
  }

  var initialStatusDetail: String {
    "Focus · 25:00 remaining"
  }

  func start() {}

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    let dt = max(0, context.now - lastTickAt)
    lastTickAt = context.now
    if context.frontmostPID == context.target.processID {
      focusedSeconds += dt
      awaySince = nil
    } else if awaySince == nil {
      awaySince = context.now
    }
    let remaining = Self.sprintDuration - (context.now - context.startedAt)
    if remaining <= 0 {
      return .completeNow
    }
    let countdown = SessionRecord.formatDuration(remaining)
    let awayDuration = awaySince.map { context.now - $0 } ?? 0
    let status =
      awayDuration >= Self.distractionThresholdSeconds
      ? "Come back to \(context.target.appName) 👀 · \(countdown)"
      : "Focus · \(countdown) left"
    return .keepRunning(statusDetail: status)
  }

  func finalize(_ context: SkillFinalizeContext) -> SkillCompletionOutcome? {
    let duration = max(0, context.now - context.startedAt)
    let ratio = duration > 0 ? Int((focusedSeconds / duration * 100).rounded()) : 100
    let summary =
      "Focused on \(context.target.appName) for \(SessionRecord.formatDuration(focusedSeconds)) (\(ratio)% on-target)."
    let record = SessionRecord(
      kind: .focus,
      characterID: context.companionID,
      characterName: context.companionName,
      appName: context.target.appName,
      bundleIdentifier: context.target.bundleIdentifier,
      windowTitle: context.target.windowTitle,
      durationSeconds: duration,
      summary: summary)
    return SkillCompletionOutcome(
      record: record, image: nil,
      bannerSummary: "Focus logged (\(SessionRecord.formatDuration(focusedSeconds)))")
  }

  func cancel() {}
}
