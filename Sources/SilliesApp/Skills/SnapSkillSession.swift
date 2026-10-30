import AppKit
import Foundation
import SilliesCore

struct SnapshotSkillRequest {
  let kind: CompanionSkillKind
  let companionID: String
  let companionName: String
  let target: WindowTargetCandidate
}

@MainActor
final class SnapSkillSession: ActiveSkillSession {
  private let request: SnapshotSkillRequest
  private let onComplete: (SkillCompletionOutcome) -> Void
  private var captureTask: Task<Void, Never>?

  init(request: SnapshotSkillRequest, onComplete: @escaping (SkillCompletionOutcome) -> Void) {
    self.request = request
    self.onComplete = onComplete
  }

  var initialStatusDetail: String { "Capturing \(request.target.appName)…" }

  func start() {
    let request = request
    captureTask = Task { [weak self] in
      let result = await WindowSnapshotService.capture(target: request.target)
      guard !Task.isCancelled, let self else { return }
      if request.kind == .snap, let png = result.pngData {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
      }
      var text = ""
      var notice = ""
      if request.kind == .explain, let image = result.image {
        do { text = try await WindowTextRecognition.recognize(image) } catch {
          notice = "Text recognition failed: \(error.localizedDescription)"
          fputs("\(notice)\n", stderr)
        }
        if text.isEmpty, notice.isEmpty {
          notice =
            "No readable text was found. Explain works from visible text; it cannot infer hidden content or interpret images alone."
        }
      }
      guard !Task.isCancelled else { return }
      let pending = request.kind == .explain && !text.isEmpty
      let record = SessionRecord(
        kind: request.kind,
        origin: .init(
          characterID: request.companionID, characterName: request.companionName,
          source: .init(
            appName: request.target.appName, bundleIdentifier: request.target.bundleIdentifier,
            windowTitle: request.target.windowTitle)),
        content: .init(
          text: .init(extractedText: text),
          notes: .init(summary: pending ? "Preparing a local explanation…" : result.summary),
          processing: .init(summaryPending: pending, failure: result.failure, note: notice)))
      let banner =
        result.pngData == nil
        ? "Capture unavailable · View details"
        : (request.kind == .snap ? "Snapshot copied to clipboard" : "Text ready · Open explanation")
      self.onComplete(
        SkillCompletionOutcome(
          record: record, image: result.image,
          pngData: result.pngData, bannerSummary: banner))
    }
  }

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    .keepRunning(statusDetail: context.currentDetail)
  }

  func finish(
    _: SkillFinalizeContext, completion: @escaping @MainActor (SkillCompletionOutcome?) -> Void
  ) {
    cancel()
    completion(nil)
  }
  func cancel() {
    captureTask?.cancel()
    captureTask = nil
  }
}
