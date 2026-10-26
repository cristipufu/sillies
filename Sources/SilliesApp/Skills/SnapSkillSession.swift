import AppKit
import Foundation
import SilliesCore

@MainActor
final class SnapSkillSession: ActiveSkillSession {
  let companionID: String
  let companionName: String
  let target: WindowTargetCandidate
  let onComplete: (SkillCompletionOutcome) -> Void
  private var captureTask: Task<Void, Never>?

  init(
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate,
    onComplete: @escaping (SkillCompletionOutcome) -> Void
  ) {
    self.companionID = companionID
    self.companionName = companionName
    self.target = target
    self.onComplete = onComplete
  }

  var initialStatusDetail: String {
    "Capturing \(target.appName)…"
  }

  func start() {
    let target = self.target
    let companionID = self.companionID
    let companionName = self.companionName
    captureTask = Task { @MainActor [weak self] in
      let result = await WindowSnapshotService.capture(target: target)
      guard !Task.isCancelled, let self else { return }
      if let pngData = result.pngData {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        if !result.extractedText.isEmpty {
          pasteboard.setString(result.extractedText, forType: .string)
        }
      }
      let record = SessionRecord(
        kind: .snap,
        characterID: companionID,
        characterName: companionName,
        appName: target.appName,
        bundleIdentifier: target.bundleIdentifier,
        windowTitle: target.windowTitle,
        extractedText: result.extractedText,
        summary: result.summary,
        actionItems: result.actionItems)
      let banner =
        result.image == nil
        ? "Permission needed · View details"
        : (result.extractedText.isEmpty
          ? "Snapshot copied & saved"
          : "Captured + OCR text ready")
      self.onComplete(
        SkillCompletionOutcome(
          record: record, image: result.image, pngData: result.pngData, bannerSummary: banner))
    }
  }

  func tick(
    now: TimeInterval,
    startedAt: TimeInterval,
    currentDetail: String,
    currentAudioLevel: Double,
    target: WindowTargetCandidate,
    snapshot: WindowTargetSnapshot?,
    frontmostPID: pid_t?
  ) -> SkillTickDisposition {
    .keepRunning(statusDetail: currentDetail, audioLevel: currentAudioLevel)
  }

  func finalize(
    now: TimeInterval,
    startedAt: TimeInterval,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate
  ) -> SkillCompletionOutcome? {
    captureTask?.cancel()
    captureTask = nil
    return nil
  }

  func cancel() {
    captureTask?.cancel()
    captureTask = nil
  }
}
