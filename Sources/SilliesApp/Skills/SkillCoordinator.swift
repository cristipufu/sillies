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
  private static let distractionThresholdSeconds: TimeInterval = 25

  private struct WatchContext {
    let initialTitle: String?
    let initialFrame: CGRect
    var sawChange = false
    var changedAt: TimeInterval = 0
    var latestTitle: String?
  }

  private struct FocusContext {
    let target: WindowTargetCandidate
    let startedAt: TimeInterval
    var lastTickAt: TimeInterval
    var focusedSeconds: Double = 0
    var awaySince: TimeInterval?
  }

  let vault: SessionVaultStore
  var onBindingChanged: ((String, CompanionBindingState) -> Void)?
  var onEmitEvent: ((String, WorkspaceEvent) -> Void)?
  var onOpenVaultRecord: ((UUID) -> Void)?

  private var audioServices: [String: AudioTranscriptionService] = [:]
  private var liveTranscripts: [String: String] = [:]
  private var watchContexts: [String: WatchContext] = [:]
  private var focusContexts: [String: FocusContext] = [:]
  private var bindings: [String: CompanionBindingState] = [:]
  private var companionNames: [String: String] = [:]
  private var tickTimer: Timer?
  private let metadataQueue = DispatchQueue(label: "app.sillies.skill-metadata", qos: .utility)

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

    switch skill {
    case .snap:
      setBinding(
        .active(
          target: target, skill: .snap, startedAt: now,
          statusDetail: "Capturing \(target.appName)…"),
        for: companionID)
      Task { @MainActor [weak self] in
        let result = await WindowSnapshotService.capture(target: target)
        guard let self else { return }
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
        self.vault.add(record, image: result.image)
        let banner =
          result.image == nil
          ? "Permission needed · View details"
          : (result.extractedText.isEmpty
            ? "Snapshot copied & saved"
            : "Captured + OCR text ready")
        let finishTime = ProcessInfo.processInfo.systemUptime
        self.onEmitEvent?(companionID, WorkspaceEvent(.skillCompleted, at: finishTime))
        self.setBinding(
          .completed(
            target: target, skill: .snap, summary: banner, recordID: record.id,
            expiresAt: finishTime + Self.completionBannerDuration),
          for: companionID)
      }

    case .listen:
      setBinding(
        .active(
          target: target, skill: .listen, startedAt: now,
          statusDetail: "Listening to \(target.appName)…"),
        for: companionID)
      let service = AudioTranscriptionService(target: target) { [weak self] update in
        Task { @MainActor [weak self] in
          guard let self else { return }
          guard
            case .active(let currentTarget, .listen, let startedAt, _, _) =
              self.binding(for: companionID)
          else { return }
          self.liveTranscripts[companionID] = update.transcript
          self.setBinding(
            .active(
              target: currentTarget, skill: .listen, startedAt: startedAt,
              statusDetail: update.statusMessage, audioLevel: update.audioLevel),
            for: companionID)
        }
      }
      audioServices[companionID] = service
      Task {
        await service.start()
      }

    case .watch:
      watchContexts[companionID] = WatchContext(
        initialTitle: target.windowTitle, initialFrame: target.frame)
      setBinding(
        .active(
          target: target, skill: .watch, startedAt: now,
          statusDetail: "Watching \(target.appName)…"),
        for: companionID)

    case .focus:
      focusContexts[companionID] = FocusContext(
        target: target, startedAt: now, lastTickAt: now)
      setBinding(
        .active(
          target: target, skill: .focus, startedAt: now,
          statusDetail: "Focus · 25:00 remaining"),
        for: companionID)

    case .stash:
      break
    }
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
    let ids = Array(bindings.keys)
    for id in ids {
      cancelActiveSkill(for: id, savePartial: true)
    }
    bindings.removeAll()
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func finalizeActiveSkill(for companionID: String) {
    let now = ProcessInfo.processInfo.systemUptime
    let characterName = companionNames[companionID] ?? companionID.capitalized
    guard case .active(let target, let skill, let startedAt, _, _) = binding(for: companionID)
    else {
      setBinding(.followingFocusedWindow, for: companionID)
      return
    }
    let duration = max(0, now - startedAt)

    switch skill {
    case .listen:
      let service = audioServices.removeValue(forKey: companionID)
      let stoppedText = service?.stop() ?? ""
      let transcript =
        stoppedText.isEmpty ? (liveTranscripts[companionID] ?? "") : stoppedText
      liveTranscripts.removeValue(forKey: companionID)
      let fallback =
        transcript.isEmpty
        ? "Audio session on \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
        : "Transcribed \(target.displayTitle) (\(SessionRecord.formatDuration(duration)))."
      let (summary, actions) = SessionSummarizer.summarize(
        text: transcript, fallbackContext: fallback)
      let record = SessionRecord(
        kind: .listen,
        characterID: companionID,
        characterName: characterName,
        appName: target.appName,
        bundleIdentifier: target.bundleIdentifier,
        windowTitle: target.windowTitle,
        durationSeconds: duration,
        transcript: transcript,
        summary: summary,
        actionItems: actions)
      vault.add(record)
      onEmitEvent?(companionID, WorkspaceEvent(.skillCompleted, at: now))
      setBinding(
        .completed(
          target: target, skill: .listen,
          summary: transcript.isEmpty ? "Audio session saved" : "Transcript & summary saved",
          recordID: record.id, expiresAt: now + Self.completionBannerDuration),
        for: companionID)

    case .watch:
      let context = watchContexts.removeValue(forKey: companionID)
      let note =
        context?.latestTitle.map { "Window updated to “\($0)”" }
        ?? "Watched \(target.displayTitle) for \(SessionRecord.formatDuration(duration))."
      let record = SessionRecord(
        kind: .watch,
        characterID: companionID,
        characterName: characterName,
        appName: target.appName,
        bundleIdentifier: target.bundleIdentifier,
        windowTitle: context?.latestTitle ?? target.windowTitle,
        durationSeconds: duration,
        summary: note)
      vault.add(record)
      onEmitEvent?(companionID, WorkspaceEvent(.skillCompleted, at: now))
      setBinding(
        .completed(
          target: target, skill: .watch, summary: "Watch complete · Focus \(target.appName)",
          recordID: record.id, expiresAt: now + Self.completionBannerDuration),
        for: companionID)

    case .focus:
      let context = focusContexts.removeValue(forKey: companionID)
      let focused = context?.focusedSeconds ?? duration
      let ratio = duration > 0 ? Int((focused / duration * 100).rounded()) : 100
      let summary =
        "Focused on \(target.appName) for \(SessionRecord.formatDuration(focused)) (\(ratio)% on-target)."
      let record = SessionRecord(
        kind: .focus,
        characterID: companionID,
        characterName: characterName,
        appName: target.appName,
        bundleIdentifier: target.bundleIdentifier,
        windowTitle: target.windowTitle,
        durationSeconds: duration,
        summary: summary)
      vault.add(record)
      onEmitEvent?(companionID, WorkspaceEvent(.skillCompleted, at: now))
      setBinding(
        .completed(
          target: target, skill: .focus,
          summary: "Focus logged (\(SessionRecord.formatDuration(focused)))",
          recordID: record.id, expiresAt: now + Self.completionBannerDuration),
        for: companionID)

    case .snap, .stash:
      setBinding(.followingFocusedWindow, for: companionID)
    }
  }

  private func cancelActiveSkill(for companionID: String, savePartial: Bool) {
    if savePartial,
      case .active(_, let skill, _, _, _) = binding(for: companionID),
      skill == .listen || skill == .focus
    {
      finalizeActiveSkill(for: companionID)
      return
    }
    if let service = audioServices.removeValue(forKey: companionID) {
      _ = service.stop()
    }
    liveTranscripts.removeValue(forKey: companionID)
    watchContexts.removeValue(forKey: companionID)
    focusContexts.removeValue(forKey: companionID)
  }

  private func setBinding(_ state: CompanionBindingState, for companionID: String) {
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
    let windowIDs = Set(bindings.values.compactMap { $0.boundTarget?.windowID })
    guard !windowIDs.isEmpty else {
      bindings.removeAll()
      updateClock()
      return
    }
    let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
    metadataQueue.async { [weak self] in
      var snapshots: [CGWindowID: (frame: CGRect, title: String?)] = [:]
      for windowID in windowIDs {
        if let snapshot = WindowTargetResolver.currentSnapshot(
          for: windowID, primaryScreenTop: primaryTop)
        {
          snapshots[windowID] = snapshot
        }
      }
      Task { @MainActor [weak self] in
        self?.applyTickSnapshots(snapshots)
      }
    }
  }

  private func applyTickSnapshots(
    _ snapshots: [CGWindowID: (frame: CGRect, title: String?)]
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
        switch skill {
        case .listen:
          if snapshot == nil {
            finalizeActiveSkill(for: companionID)
          } else {
            let elapsed = SessionRecord.formatDuration(now - startedAt)
            let prefix = "\(elapsed) · "
            let cleanDetail =
              detail.hasPrefix(prefix)
              ? detail
              : "\(elapsed) · \(detail.replacingOccurrences(of: #"^\d{2}:\d{2} · "#, with: "", options: .regularExpression))"
            setBinding(
              .active(
                target: target, skill: .listen, startedAt: startedAt,
                statusDetail: cleanDetail, audioLevel: audioLevel),
              for: companionID)
          }

        case .watch:
          guard let snapshot else {
            finalizeActiveSkill(for: companionID)
            continue
          }
          var context =
            watchContexts[companionID]
            ?? WatchContext(initialTitle: target.windowTitle, initialFrame: snapshot.frame)
          if let currentTitle = snapshot.title, currentTitle != context.initialTitle {
            context.sawChange = true
            context.latestTitle = currentTitle
            if context.changedAt == 0 { context.changedAt = now }
          }
          if abs(snapshot.frame.width - context.initialFrame.width) > 12
            || abs(snapshot.frame.height - context.initialFrame.height) > 12
          {
            context.sawChange = true
            if context.changedAt == 0 { context.changedAt = now }
          }
          watchContexts[companionID] = context
          if context.sawChange && now - context.changedAt >= 1.5 {
            finalizeActiveSkill(for: companionID)
          } else {
            let elapsed = SessionRecord.formatDuration(now - startedAt)
            setBinding(
              .active(
                target: target, skill: .watch, startedAt: startedAt,
                statusDetail: "Watching \(target.appName) · \(elapsed)"),
              for: companionID)
          }

        case .focus:
          guard var context = focusContexts[companionID] else { continue }
          let dt = max(0, now - context.lastTickAt)
          context.lastTickAt = now
          let isTargetActive = frontmostPID == target.processID
          if isTargetActive {
            context.focusedSeconds += dt
            context.awaySince = nil
          } else if context.awaySince == nil {
            context.awaySince = now
          }
          focusContexts[companionID] = context
          let remaining = Self.focusSprintDuration - (now - startedAt)
          if remaining <= 0 {
            finalizeActiveSkill(for: companionID)
          } else {
            let countdown = SessionRecord.formatDuration(remaining)
            let awayDuration = context.awaySince.map { now - $0 } ?? 0
            let status =
              awayDuration >= Self.distractionThresholdSeconds
              ? "Come back to \(target.appName) 👀 · \(countdown)"
              : "Focus · \(countdown) left"
            setBinding(
              .active(
                target: target, skill: .focus, startedAt: startedAt, statusDetail: status),
              for: companionID)
          }

        case .snap, .stash:
          break
        }
      }
    }
    updateClock()
  }
}
