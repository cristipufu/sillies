import AppKit
import Foundation
import Observation
import SilliesCore

/// Coordinates window-bound companion skills (Snap & OCR, Listen & Scribe, Watch Window,
/// Focus Sprint, and Pocket Stash) with a single shared lifecycle timer when active.
@MainActor @Observable
final class SkillCoordinator {
  typealias SnapshotLoader =
    @Sendable (Set<CGWindowID>, Double) async -> [CGWindowID: WindowTargetSnapshot]

  static let selectionPromptDuration: TimeInterval = 5.5
  static let completionBannerDuration: TimeInterval = 6.5
  static let focusSprintDuration: TimeInterval = FocusSkillSession.sprintDuration

  private struct TickRequestContext {
    let token: UInt64
    let windowID: CGWindowID
  }

  let vault: SessionVaultStore
  var onBindingChanged: ((String, CompanionBindingState) -> Void)?
  var onEmitEvent: ((String, WorkspaceEvent) -> Void)?
  var onOpenVaultRecord: ((UUID) -> Void)?

  @ObservationIgnored private let snapshotLoader: SnapshotLoader
  private var sessions: [String: any ActiveSkillSession] = [:]
  private var bindings: [String: CompanionBindingState] = [:]
  private var bindingTokens: [String: UInt64] = [:]
  private var nextBindingToken: UInt64 = 0
  private var companionNames: [String: String] = [:]
  private var tickTimer: Timer?
  private var tickTask: Task<Void, Never>?

  init(
    vault: SessionVaultStore = SessionVaultStore(),
    snapshotLoader: @escaping SnapshotLoader = { windowIDs, primaryTop in
      await WindowTargetMetadata.shared.snapshots(for: windowIDs, primaryScreenTop: primaryTop)
    }
  ) {
    self.vault = vault
    self.snapshotLoader = snapshotLoader
    vault.resumePendingSummaries()
  }

  func binding(for companionID: String) -> CompanionBindingState {
    bindings[companionID] ?? .followingFocusedWindow
  }

  func presentSelectionPrompt(
    for companionID: String, companionName: String, target: WindowTargetCandidate
  ) {
    cancelActiveSkill(for: companionID, savePartial: true)
    companionNames[companionID] = companionName
    advanceBindingToken(for: companionID)
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
    let sessionToken = advanceBindingToken(for: companionID)
    let now = ProcessInfo.processInfo.systemUptime
    onEmitEvent?(companionID, WorkspaceEvent(skill.eventKind, at: now))

    guard
      let session = makeSession(
        for: skill, companionID: companionID, companionName: companionName, target: target,
        startedAt: now, sessionToken: sessionToken)
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
    let existingBinding = binding(for: companionID)
    let resolvedTarget = existingBinding.boundTarget ?? currentTarget
    let fallback = "Stashed \(cleaned.count) item(s) with \(companionName)."
    let record = SessionRecord(
      kind: .stash,
      characterID: companionID,
      characterName: companionName,
      appName: resolvedTarget?.appName ?? "Workspace",
      bundleIdentifier: resolvedTarget?.bundleIdentifier,
      windowTitle: resolvedTarget?.windowTitle,
      summary: fallback,
      actionItems: [],
      stashedItems: cleaned,
      summaryPending: true)
    vault.add(record)
    onEmitEvent?(companionID, WorkspaceEvent(.stashReceived, at: now))

    let countLabel = "Stashed \(cleaned.count) item\(cleaned.count == 1 ? "" : "s")"
    if case .active(let activeTarget, let activeSkill, let startedAt, _, let audioLevel) =
      existingBinding
    {
      // Preserve any ongoing recording/focus/watch session instead of replacing its active binding.
      setBinding(
        .active(
          target: activeTarget,
          skill: activeSkill,
          startedAt: startedAt,
          statusDetail: "\(countLabel) ✓",
          audioLevel: audioLevel),
        for: companionID)
    } else if let target = resolvedTarget {
      advanceBindingToken(for: companionID)
      setBinding(
        .completed(
          target: target, skill: .stash,
          summary: "\(countLabel) · Open Vault",
          recordID: record.id, expiresAt: now + Self.completionBannerDuration),
        for: companionID)
    }
  }

  func stopSkill(for companionID: String) {
    finalizeActiveSkill(for: companionID)
  }

  func unbind(companionID: String) {
    cancelActiveSkill(for: companionID, savePartial: true)
    advanceBindingToken(for: companionID)
    setBinding(.followingFocusedWindow, for: companionID)
  }

  func stopAll() {
    let ids = Array(Set(bindings.keys).union(sessions.keys))
    for id in ids {
      cancelActiveSkill(for: id, savePartial: true)
      advanceBindingToken(for: id)
    }
    bindings.removeAll()
    tickTask?.cancel()
    tickTask = nil
    tickTimer?.invalidate()
    tickTimer = nil
  }

  /// Stops active sessions, cancels in-flight background summary tasks so pending records remain
  /// marked `summaryPending` for next launch, and awaits queued vault disk writes.
  func shutdown() async {
    stopAll()
    vault.cancelPendingSummaries()
    await vault.flush()
  }

  /// Triggers an immediate metadata tick (used by the 1 Hz timer and unit tests).
  func pollBoundWindows() {
    tick()
  }

  /// Resumes any persisted `SessionRecord` whose summary was still pending when the previous
  /// session exited.
  func resumePendingSummaries() {
    vault.resumePendingSummaries()
  }

  /// Waits for any in-flight background transcript or stash summary tasks to finish.
  func flushPendingSummaries() async {
    await vault.flushPendingSummaries()
  }

  @discardableResult
  private func advanceBindingToken(for companionID: String) -> UInt64 {
    nextBindingToken &+= 1
    bindingTokens[companionID] = nextBindingToken
    return nextBindingToken
  }

  private func makeSession(
    for skill: CompanionSkillKind,
    companionID: String,
    companionName: String,
    target: WindowTargetCandidate,
    startedAt: TimeInterval,
    sessionToken: UInt64
  ) -> (any ActiveSkillSession)? {
    switch skill {
    case .snap:
      return SnapSkillSession(
        companionID: companionID,
        companionName: companionName,
        target: target
      ) { [weak self] outcome in
        guard let self, self.bindingTokens[companionID] == sessionToken else { return }
        self.completeSession(
          outcome, for: companionID, skill: .snap, target: target,
          at: ProcessInfo.processInfo.systemUptime)
      }

    case .listen:
      return ListenSkillSession(target: target) { [weak self] statusMessage, audioLevel in
        guard let self, self.bindingTokens[companionID] == sessionToken else { return }
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
      advanceBindingToken(for: companionID)
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
    advanceBindingToken(for: companionID)
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
    if case .active = state {
      // Keep active session running.
    } else if let orphanedSession = sessions.removeValue(forKey: companionID) {
      orphanedSession.cancel()
    }
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
    var requestedContext: [String: TickRequestContext] = [:]
    for (companionID, state) in bindings {
      if let windowID = state.boundTarget?.windowID {
        let token = bindingTokens[companionID] ?? 0
        requestedContext[companionID] = TickRequestContext(token: token, windowID: windowID)
      }
    }
    let windowIDs = Set(requestedContext.values.map(\.windowID))
    guard !windowIDs.isEmpty else {
      bindings.removeAll()
      updateClock()
      return
    }
    let primaryTop = Double(NSScreen.screens.first?.frame.maxY ?? 0)
    let load = snapshotLoader
    tickTask = Task { @MainActor [weak self] in
      let snapshots = await load(windowIDs, primaryTop)
      guard !Task.isCancelled, let self else { return }
      self.tickTask = nil
      self.applyTickSnapshots(snapshots, requestedContext: requestedContext)
    }
  }

  private func applyTickSnapshots(
    _ snapshots: [CGWindowID: WindowTargetSnapshot],
    requestedContext: [String: TickRequestContext]
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var needsFollowupTick = false
    for (companionID, state) in bindings {
      guard let requested = requestedContext[companionID],
        requested.token == (bindingTokens[companionID] ?? 0),
        requested.windowID == state.boundTarget?.windowID
      else {
        needsFollowupTick = true
        continue
      }

      switch state {
      case .followingFocusedWindow:
        bindings.removeValue(forKey: companionID)

      case .awaitingSelection(var target, let expiresAt):
        if now >= expiresAt {
          advanceBindingToken(for: companionID)
          setBinding(.followingFocusedWindow, for: companionID)
        } else if let snapshot = snapshots[target.windowID] {
          if snapshot.frame != target.frame {
            target.frame = snapshot.frame
            setBinding(
              .awaitingSelection(target: target, expiresAt: expiresAt), for: companionID)
          }
        } else {
          advanceBindingToken(for: companionID)
          setBinding(.followingFocusedWindow, for: companionID)
        }

      case .completed(var target, let skill, let summary, let recordID, let expiresAt):
        if now >= expiresAt {
          advanceBindingToken(for: companionID)
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
    if needsFollowupTick && !bindings.isEmpty {
      tick()
    }
  }
}
