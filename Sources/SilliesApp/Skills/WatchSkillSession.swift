import CoreGraphics
import Foundation
import SilliesCore

@MainActor
final class WatchSkillSession: ActiveSkillSession {
  private static let significantFrameChangeThreshold: CGFloat = 12
  private static let changeSettleDelay: TimeInterval = 1.5

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

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    guard let snapshot = context.snapshot else { return .completeNow }
    if let currentTitle = snapshot.title, currentTitle != initialTitle {
      sawChange = true
      latestTitle = currentTitle
      if changedAt == 0 { changedAt = context.now }
    }
    if abs(snapshot.frame.width - initialFrame.width) > Self.significantFrameChangeThreshold
      || abs(snapshot.frame.height - initialFrame.height) > Self.significantFrameChangeThreshold
    {
      sawChange = true
      if changedAt == 0 { changedAt = context.now }
    }
    if sawChange && context.now - changedAt >= Self.changeSettleDelay {
      return .completeNow
    }
    let elapsed = SessionRecord.formatDuration(context.now - context.startedAt)
    return .keepRunning(statusDetail: "Watching \(context.target.appName) · \(elapsed)")
  }

  func finalize(_ context: SkillFinalizeContext) -> SkillCompletionOutcome? {
    let duration = max(0, context.now - context.startedAt)
    let note =
      latestTitle.map { "Window updated to “\($0)”" }
      ?? "Watched \(context.target.displayTitle) for \(SessionRecord.formatDuration(duration))."
    let record = SessionRecord(
      kind: .watch,
      characterID: context.companionID,
      characterName: context.companionName,
      appName: context.target.appName,
      bundleIdentifier: context.target.bundleIdentifier,
      windowTitle: latestTitle ?? context.target.windowTitle,
      durationSeconds: duration,
      summary: note)
    return SkillCompletionOutcome(
      record: record, image: nil, bannerSummary: "Watch complete · Focus \(context.target.appName)")
  }

  func cancel() {}
}
