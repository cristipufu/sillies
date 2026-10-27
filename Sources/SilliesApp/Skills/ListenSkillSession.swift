import Foundation
import SilliesCore

@MainActor
final class ListenSkillSession: ActiveSkillSession {
  let target: WindowTargetCandidate
  let onLiveUpdate: (String, Double) -> Void
  private var service: AudioTranscriptionService?
  private var liveTranscript = ""
  private var latestStatusMessage: String

  init(target: WindowTargetCandidate, onLiveUpdate: @escaping (String, Double) -> Void) {
    self.target = target
    self.onLiveUpdate = onLiveUpdate
    self.latestStatusMessage = "Listening to \(target.appName)…"
  }

  var initialStatusDetail: String {
    latestStatusMessage
  }

  func start() {
    let service = AudioTranscriptionService(target: target) { [weak self] update in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let transcript = update.transcript, !transcript.isEmpty {
          self.liveTranscript = transcript
        }
        self.latestStatusMessage = update.statusMessage
        self.onLiveUpdate(update.statusMessage, update.audioLevel)
      }
    }
    self.service = service
    Task {
      await service.start()
    }
  }

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    guard context.snapshot != nil else { return .completeNow }
    let elapsed = SessionRecord.formatDuration(context.now - context.startedAt)
    return .keepRunning(
      statusDetail: "\(elapsed) · \(latestStatusMessage)",
      audioLevel: context.currentAudioLevel)
  }

  func finalize(_ context: SkillFinalizeContext) -> SkillCompletionOutcome? {
    let duration = max(0, context.now - context.startedAt)
    let stoppedText = service?.stop() ?? ""
    service = nil
    let transcript = stoppedText.isEmpty ? liveTranscript : stoppedText
    let hasTranscript = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let fallback =
      hasTranscript
      ? "Transcribed \(context.target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
      : "Audio session on \(context.target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
    let record = SessionRecord(
      kind: .listen,
      characterID: context.companionID,
      characterName: context.companionName,
      appName: context.target.appName,
      bundleIdentifier: context.target.bundleIdentifier,
      windowTitle: context.target.windowTitle,
      durationSeconds: duration,
      transcript: transcript,
      summary: fallback,
      actionItems: [],
      summaryPending: hasTranscript)
    let banner = hasTranscript ? "Transcript & summary saved" : "Audio session saved"
    return SkillCompletionOutcome(
      record: record,
      image: nil,
      bannerSummary: banner)
  }

  func cancel() {
    _ = service?.stop()
    service = nil
  }
}
