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
        self.liveTranscript = update.transcript
        self.latestStatusMessage = update.statusMessage
        self.onLiveUpdate(update.statusMessage, update.audioLevel)
      }
    }
    self.service = service
    Task {
      await service.start()
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
    guard snapshot != nil else { return .completeNow }
    let elapsed = SessionRecord.formatDuration(now - startedAt)
    return .keepRunning(
      statusDetail: "\(elapsed) · \(latestStatusMessage)",
      audioLevel: currentAudioLevel)
  }

  func finalize(
    now: TimeInterval,
    startedAt: TimeInterval,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate
  ) -> SkillCompletionOutcome? {
    let duration = max(0, now - startedAt)
    let stoppedText = service?.stop() ?? ""
    service = nil
    let transcript = stoppedText.isEmpty ? liveTranscript : stoppedText
    let hasTranscript = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let fallback =
      hasTranscript
      ? "Transcribed \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
      : "Audio session on \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
    let record = SessionRecord(
      kind: .listen,
      characterID: companionID,
      characterName: companionName,
      appName: target.appName,
      bundleIdentifier: target.bundleIdentifier,
      windowTitle: target.windowTitle,
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
