import CoreGraphics
import Foundation
import SilliesCore

@MainActor
final class WatchSkillSession: ActiveSkillSession {
  let target: WindowTargetCandidate
  private let initialTitle: String?
  private let initialFrame: CGRect
  private var sawChange = false
  private var changedAt: TimeInterval = 0
  private var latestTitle: String?

  init(target: WindowTargetCandidate) {
    self.target = target
    self.initialTitle = target.windowTitle
    self.initialFrame = target.frame
  }

  var initialStatusDetail: String {
    "Watching \(target.appName)…"
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
    guard let snapshot else { return .completeNow }
    if let currentTitle = snapshot.title, currentTitle != initialTitle {
      sawChange = true
      latestTitle = currentTitle
      if changedAt == 0 { changedAt = now }
    }
    if abs(snapshot.frame.width - initialFrame.width) > 12
      || abs(snapshot.frame.height - initialFrame.height) > 12
    {
      sawChange = true
      if changedAt == 0 { changedAt = now }
    }
    if sawChange && now - changedAt >= 1.5 {
      return .completeNow
    }
    let elapsed = SessionRecord.formatDuration(now - startedAt)
    return .keepRunning(statusDetail: "Watching \(target.appName) · \(elapsed)")
  }

  func finalize(
    now: TimeInterval,
    startedAt: TimeInterval,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate
  ) -> SkillCompletionOutcome? {
    let duration = max(0, now - startedAt)
    let note =
      latestTitle.map { "Window updated to “\($0)”" }
      ?? "Watched \(target.displayTitle) for \(SessionRecord.formatDuration(duration))."
    let record = SessionRecord(
      kind: .watch,
      characterID: companionID,
      characterName: companionName,
      appName: target.appName,
      bundleIdentifier: target.bundleIdentifier,
      windowTitle: latestTitle ?? target.windowTitle,
      durationSeconds: duration,
      summary: note)
    return SkillCompletionOutcome(
      record: record, image: nil, bannerSummary: "Watch complete · Focus \(target.appName)")
  }

  func cancel() {}
}
