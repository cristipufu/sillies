import AppKit
import Foundation
import Observation
import SilliesCore

/// Coordinates window-bound companion skills (Snap & OCR, Listen & Scribe, Watch Window,
/// Focus Sprint, and Pocket Stash) with a single shared lifecycle timer when active.
@MainActor @Observable
final class SkillCoordinator {
  static let selectionPromptDuration: TimeInterval = 5.5
  static let completionBannerDuration: TimeInterval = 6.5
  static let focusSprintDuration: TimeInterval = 25 * 60
  fileprivate static let distractionThresholdSeconds: TimeInterval = 25

  let vault: SessionVaultStore
  var onBindingChanged: ((String, CompanionBindingState) -> Void)?
  var onEmitEvent: ((String, WorkspaceEvent) -> Void)?
  var onOpenVaultRecord: ((UUID) -> Void)?

  private var sessions: [String: any ActiveSkillSession] = [:]
  private var bindings: [String: CompanionBindingState] = [:]
  private var companionNames: [String: String] = [:]
  private var tickTimer: Timer?
  private var tickTask: Task<Void, Never>?

  init(vault: SessionVaultStore = SessionVaultStore()) {
    self.vault = vault
  }

  func binding(for companionID: String) -> CompanionBindingState {
    bindings[companionID] ?? .followingFocusedWindow
  }

  func presentSelectionPrompt(
    for companionID: String, companionName: String, target: WindowTargetCandidate
  ) {
    cancelActiveSkill(for: companionID, savePartial: true)
    companionNames[companionID] = companionName
    let now = ProcessInfo.processInfo.systemUptime
    let state = CompanionBindingState.awaitingSelection(
      target: target, expiresAt: now + Self.selectionPromptDuration)
    setBinding(state, for: companionID)
  }

  func startSkill(
    _ skill: CompanionSkillKind, for companionID: String, companionName: String,
    target: WindowTargetCandidate
  ) {
    cancelActiveSkill(for: companionID, savePartial: true)
    companionNames[companionID] = companionName
    let now = ProcessInfo.processInfo.systemUptime
    onEmitEvent?(companionID, WorkspaceEvent(skill.eventKind, at: now))

    guard
      let session = makeSession(
        for: skill, companionID: companionID, companionName: companionName, target: target,
        startedAt: now)
    else { return }

    sessions[companionID] = session
    setBinding(
      .active(
        target: target, skill: skill, startedAt: now,
        statusDetail: session.initialStatusDetail),
      for: companionID)
    session.start()
  }

  func recordStash(
    items: [String], for companionID: String, companionName: String,
    currentTarget: WindowTargetCandidate?
  ) {
    let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      !$0.isEmpty
    }
    guard !cleaned.isEmpty else { return }
    companionNames[companionID] = companionName
    let now = ProcessInfo.processInfo.systemUptime
    let combined = cleaned.joined(separator: "\n")
    let (summary, actions) = SessionSummarizer.summarize(
      text: combined, fallbackContext: "Stashed \(cleaned.count) item(s) with \(companionName).")
    let record = SessionRecord(
      kind: .stash,
      characterID: companionID,
      characterName: companionName,
      appName: currentTarget?.appName ?? "Workspace",
      bundleIdentifier: currentTarget?.bundleIdentifier,
      windowTitle: currentTarget?.windowTitle,
      summary: summary,
      actionItems: actions,
      stashedItems: cleaned)
    vault.add(record)
    onEmitEvent?(companionID, WorkspaceEvent(.stashReceived, at: now))
    if let target = currentTarget {
      setBinding(
        .completed(
          target: target, skill: .stash,
          summary: "Stashed \(cleaned.count) item\(cleaned.count == 1 ? "" : "s") · Open Vault",
          recordID: record.id, expiresAt: now + Self.completionBannerDuration),
        for: companionID)
    }
  }

  func stopSkill(for companionID: String) {
    finalizeActiveSkill(for: companionID)
  }

  func unbind(companionID: String) {
    cancelActiveSkill(for: companionID, savePartial: true)
    setBinding(.followingFocusedWindow, for: companionID)
  }

  func stopAll() {
    let ids = Array(Set(bindings.keys).union(sessions.keys))
    for id in ids {
      cancelActiveSkill(for: id, savePartial: true)
    }
    bindings.removeAll()
    tickTask?.cancel()
    tickTask = nil
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func makeSession(
    for skill: CompanionSkillKind,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate,
    startedAt: TimeInterval
  ) -> (any ActiveSkillSession)? {
    switch skill {
    case .snap:
      return SnapSkillSession(
        companionID: companionID,
        companionName: companionName,
        target: target
      ) { [weak self] outcome in
        self?.completeSession(
          outcome, for: companionID, skill: .snap, target: target,
          at: ProcessInfo.processInfo.systemUptime)
      }

    case .listen:
      return ListenSkillSession(target: target) { [weak self] statusMessage, audioLevel in
        guard let self else { return }
        guard
          case .active(let currentTarget, .listen, let activeStartedAt, _, _) =
            self.binding(for: companionID)
        else { return }
        self.setBinding(
          .active(
            target: currentTarget, skill: .listen, startedAt: activeStartedAt,
            statusDetail: statusMessage, audioLevel: audioLevel),
          for: companionID)
      }

    case .watch:
      return WatchSkillSession(target: target)

    case .focus:
      return FocusSkillSession(target: target, startedAt: startedAt)

    case .stash:
      return nil
    }
  }

  private func finalizeActiveSkill(for companionID: String) {
    let now = ProcessInfo.processInfo.systemUptime
    let characterName = companionNames[companionID] ?? companionID.capitalized
    let session = sessions.removeValue(forKey: companionID)
    guard case .active(let target, let skill, let startedAt, _, _) = binding(for: companionID),
      let outcome = session?.finalize(
        now: now, startedAt: startedAt, companionID: companionID,
        companionName: characterName, target: target)
    else {
      session?.cancel()
      setBinding(.followingFocusedWindow, for: companionID)
      return
    }
    completeSession(outcome, for: companionID, skill: skill, target: target, at: now)
  }

  private func completeSession(
    _ outcome: SkillCompletionOutcome,
    for companionID: String,
    skill: CompanionSkillKind,
    target: WindowTargetCandidate,
    at now: TimeInterval
  ) {
    sessions.removeValue(forKey: companionID)
    vault.add(outcome.record, image: outcome.image)
    onEmitEvent?(companionID, WorkspaceEvent(.skillCompleted, at: now))
    setBinding(
      .completed(
        target: target, skill: skill, summary: outcome.bannerSummary,
        recordID: outcome.record.id, expiresAt: now + Self.completionBannerDuration),
      for: companionID)
  }

  private func cancelActiveSkill(for companionID: String, savePartial: Bool) {
    if savePartial,
      case .active(_, let skill, _, _, _) = binding(for: companionID),
      skill.savesPartialOnCancel
    {
      finalizeActiveSkill(for: companionID)
      return
    }
    if let session = sessions.removeValue(forKey: companionID) {
      session.cancel()
    }
  }

  private func setBinding(_ state: CompanionBindingState, for companionID: String) {
    let existing = binding(for: companionID)
    guard existing != state else { return }
    if case .followingFocusedWindow = state {
      bindings.removeValue(forKey: companionID)
    } else {
      bindings[companionID] = state
    }
    updateClock()
    onBindingChanged?(companionID, state)
  }

  private func updateClock() {
    if bindings.isEmpty {
      tickTask?.cancel()
      tickTask = nil
      tickTimer?.invalidate()
      tickTimer = nil
      return
    }
    guard tickTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = 0.15
    RunLoop.main.add(timer, forMode: .common)
    tickTimer = timer
  }

  private func tick() {
    guard tickTask == nil else { return }
    let windowIDs = Set(bindings.values.compactMap { $0.boundTarget?.windowID })
    guard !windowIDs.isEmpty else {
      bindings.removeAll()
      updateClock()
      return
    }
    let primaryTop = Double(NSScreen.screens.first?.frame.maxY ?? 0)
    tickTask = Task { @MainActor [weak self] in
      let snapshots = await WindowTargetMetadata.shared.snapshots(
        for: windowIDs, primaryScreenTop: primaryTop)
      guard !Task.isCancelled, let self else { return }
      self.tickTask = nil
      self.applyTickSnapshots(snapshots)
    }
  }

  private func applyTickSnapshots(
    _ snapshots: [CGWindowID: WindowTargetSnapshot]
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    for (companionID, state) in bindings {
      switch state {
      case .followingFocusedWindow:
        bindings.removeValue(forKey: companionID)

      case .awaitingSelection(var target, let expiresAt):
        if now >= expiresAt {
          setBinding(.followingFocusedWindow, for: companionID)
        } else if let snapshot = snapshots[target.windowID] {
          if snapshot.frame != target.frame {
            target.frame = snapshot.frame
            setBinding(
              .awaitingSelection(target: target, expiresAt: expiresAt), for: companionID)
          }
        } else {
          setBinding(.followingFocusedWindow, for: companionID)
        }

      case .completed(var target, let skill, let summary, let recordID, let expiresAt):
        if now >= expiresAt {
          setBinding(.followingFocusedWindow, for: companionID)
        } else if let snapshot = snapshots[target.windowID],
          snapshot.frame != target.frame
        {
          target.frame = snapshot.frame
          setBinding(
            .completed(
              target: target, skill: skill, summary: summary, recordID: recordID,
              expiresAt: expiresAt),
            for: companionID)
        }

      case .active(var target, let skill, let startedAt, let detail, let audioLevel):
        let snapshot = snapshots[target.windowID]
        if let liveFrame = snapshot?.frame {
          target.frame = liveFrame
        }
        guard let session = sessions[companionID] else { continue }
        let disposition = session.tick(
          now: now,
          startedAt: startedAt,
          currentDetail: detail,
          currentAudioLevel: audioLevel,
          target: target,
          snapshot: snapshot,
          frontmostPID: frontmostPID)
        switch disposition {
        case .completeNow:
          finalizeActiveSkill(for: companionID)
        case .keepRunning(let updatedDetail, let updatedAudioLevel):
          setBinding(
            .active(
              target: target, skill: skill, startedAt: startedAt,
              statusDetail: updatedDetail, audioLevel: updatedAudioLevel),
            for: companionID)
        }
      }
    }
    updateClock()
  }
}

private struct SkillCompletionOutcome {
  let record: SessionRecord
  let image: CGImage?
  let bannerSummary: String
}

private enum SkillTickDisposition {
  case keepRunning(statusDetail: String, audioLevel: Double = 0)
  case completeNow
}

@MainActor
private protocol ActiveSkillSession: AnyObject {
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

@MainActor
private final class SnapSkillSession: ActiveSkillSession {
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
      if let cgImage = result.image {
        let nsImage = NSImage(
          cgImage: cgImage,
          size: NSSize(width: cgImage.width, height: cgImage.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
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
        SkillCompletionOutcome(record: record, image: result.image, bannerSummary: banner))
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

@MainActor
private final class ListenSkillSession: ActiveSkillSession {
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
    let fallback =
      transcript.isEmpty
      ? "Audio session on \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
      : "Transcribed \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
    let (summary, actions) = SessionSummarizer.summarize(
      text: transcript, fallbackContext: fallback)
    let record = SessionRecord(
      kind: .listen,
      characterID: companionID,
      characterName: companionName,
      appName: target.appName,
      bundleIdentifier: target.bundleIdentifier,
      windowTitle: target.windowTitle,
      durationSeconds: duration,
      transcript: transcript,
      summary: summary,
      actionItems: actions)
    let banner = transcript.isEmpty ? "Audio session saved" : "Transcript & summary saved"
    return SkillCompletionOutcome(record: record, image: nil, bannerSummary: banner)
  }

  func cancel() {
    _ = service?.stop()
    service = nil
  }
}

@MainActor
private final class WatchSkillSession: ActiveSkillSession {
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

@MainActor
private final class FocusSkillSession: ActiveSkillSession {
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
    let remaining = SkillCoordinator.focusSprintDuration - (now - startedAt)
    if remaining <= 0 {
      return .completeNow
    }
    let countdown = SessionRecord.formatDuration(remaining)
    let awayDuration = awaySince.map { now - $0 } ?? 0
    let status =
      awayDuration >= SkillCoordinator.distractionThresholdSeconds
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
