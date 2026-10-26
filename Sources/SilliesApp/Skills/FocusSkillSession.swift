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

  func tick(
    now: TimeInterval,
    startedAt: TimeInterval,
    currentDetail: String,
    currentAudioLevel: Double,
    target: WindowTargetCandidate,
    snapshot: WindowTargetSnapshot?,
    frontmostPID: pid_t?
  ) -> SkillTickDisposition {
    let dt = max(0, now - lastTickAt)
    lastTickAt = now
    if frontmostPID == target.processID {
      focusedSeconds += dt
      awaySince = nil
    } else if awaySince == nil {
      awaySince = now
    }
    let remaining = Self.sprintDuration - (now - startedAt)
    if remaining <= 0 {
      return .completeNow
    }
    let countdown = SessionRecord.formatDuration(remaining)
    let awayDuration = awaySince.map { now - $0 } ?? 0
    let status =
      awayDuration >= Self.distractionThresholdSeconds
      ? "Come back to \(target.appName) 👀 · \(countdown)"
      : "Focus · \(countdown) left"
    return .keepRunning(statusDetail: status)
  }

  func finalize(
    now: TimeInterval,
    startedAt: TimeInterval,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate
  ) -> SkillCompletionOutcome? {
    let duration = max(0, now - startedAt)
    let ratio = duration > 0 ? Int((focusedSeconds / duration * 100).rounded()) : 100
    let summary =
      "Focused on \(target.appName) for \(SessionRecord.formatDuration(focusedSeconds)) (\(ratio)% on-target)."
    let record = SessionRecord(
      kind: .focus,
      characterID: companionID,
      characterName: companionName,
      appName: target.appName,
      bundleIdentifier: target.bundleIdentifier,
      windowTitle: target.windowTitle,
      durationSeconds: duration,
      summary: summary)
    return SkillCompletionOutcome(
      record: record, image: nil,
      bannerSummary: "Focus logged (\(SessionRecord.formatDuration(focusedSeconds)))")
  }

  func cancel() {}
}
