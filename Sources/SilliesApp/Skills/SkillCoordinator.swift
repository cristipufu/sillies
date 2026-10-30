import AppKit
import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesSpeechApple

/// Owns skill lifetimes and one shared metadata clock. Capture and inference own their workers.
@MainActor @Observable
final class SkillCoordinator {
  typealias SnapshotLoader =
    @Sendable (Set<CGWindowID>, Double) async -> [CGWindowID: WindowTargetSnapshot]
  static let completionBannerDuration: TimeInterval = 6.5
  static let focusSprintDuration = FocusSkillSession.sprintDuration
  private static let tickInterval: TimeInterval = 1
  private static let tickTolerance: TimeInterval = 0.15

  private struct SessionRequest {
    let skill: CompanionSkillKind
    let companionID: String
    let companionName: String
    let target: WindowTargetCandidate?
    let startedAt: TimeInterval
    let token: UInt64
  }
  private struct TickRequest {
    let token: UInt64
    let windowID: CGWindowID?
  }

  let vault: SessionVaultStore
  var savedRecordCount: Int { vault.records.count }
  var onBindingChanged: ((String, CompanionBindingState) -> Void)?
  var onEmitEvent: ((String, WorkspaceEvent) -> Void)?
  var onOpenVaultRecord: ((UUID) -> Void)?
  var onOpenAudioSession: ((AudioSessionPresentation) -> Void)?
  private var sessions: [String: any ActiveSkillSession] = [:]
  private var bindings: [String: CompanionBindingState] = [:]
  private var bindingTokens: [String: UInt64] = [:]
  private var nextBindingToken: UInt64 = 0
  private var companionNames: [String: String] = [:]
  @ObservationIgnored private let audioFactory: SessionAudioCaptureFactory
  @ObservationIgnored private let audioLanguages: AudioLanguageEnvironment
  @ObservationIgnored private let snapshotLoader: SnapshotLoader
  private var finishingSessions: [UUID: any ActiveSkillSession] = [:]
  @ObservationIgnored private var finishWaiters: [() -> Void] = []
  @ObservationIgnored private var tickTimer: Timer?
  @ObservationIgnored private var tickTask: Task<Void, Never>?

  init(
    vault: SessionVaultStore = SessionVaultStore(),
    audioFactory: @escaping SessionAudioCaptureFactory = {
      AudioTranscriptionService(
        configuration: $0, speech: AppleSpeechProvider.makeChannel, onUpdate: $1)
    },
    audioLanguages: AudioLanguageEnvironment = .live,
    snapshotLoader: @escaping SnapshotLoader = { ids, top in
      await WindowTargetMetadata.shared.snapshots(for: ids, primaryScreenTop: top)
    }
  ) {
    self.audioFactory = audioFactory
    self.audioLanguages = audioLanguages
    self.vault = vault
    self.snapshotLoader = snapshotLoader
    vault.resumePendingSummaries()
  }

  var activeAudioSession: AudioSessionPresentation? {
    (Array(sessions.values) + Array(finishingSessions.values)).compactMap {
      ($0 as? AudioSkillSession)?.presentation
    }.first
  }

  func audioPresentation(for id: String) -> AudioSessionPresentation? {
    (sessions[id] as? AudioSkillSession)?.presentation
  }

  func binding(for id: String) -> CompanionBindingState { bindings[id] ?? .followingFocusedWindow }

  func presentation(for id: String) -> SkillPresentation {
    let completed: SessionRecord?
    if case .completed(_, _, _, let recordID, _) = binding(for: id) {
      completed = vault.records.first { $0.id == recordID }
    } else {
      completed = nil
    }
    return SkillPresentation(
      persistenceError: vault.persistenceError, completedRecord: completed,
      audioSession: audioPresentation(for: id))
  }

  func openAudioSession(for id: String) {
    if let session = audioPresentation(for: id) { onOpenAudioSession?(session) }
  }

  func openActiveAudioSession() {
    if let session = activeAudioSession { onOpenAudioSession?(session) }
  }

  func removeRecord(id: UUID) { vault.remove(id: id) }
  func whenPersisted(_ completion: @escaping @MainActor @Sendable (String?) -> Void) {
    vault.whenPersisted(completion)
  }

  func startSkill(
    _ skill: CompanionSkillKind, for id: String, companionName: String,
    target: WindowTargetCandidate? = nil
  ) {
    guard !skill.requiresWindow || target != nil else { return }
    // One audio session prevents duplicate system/microphone taps across the whole crew.
    if skill.isAudioSession, activeAudioSession != nil { return }
    finishOrCancelSession(for: id)
    companionNames[id] = companionName
    let request = SessionRequest(
      skill: skill, companionID: id, companionName: companionName,
      target: skill == .record ? nil : target, startedAt: ProcessInfo.processInfo.systemUptime,
      token: advanceBindingToken(for: id))
    guard let session = makeSession(request) else { return }
    sessions[id] = session
    setBinding(
      .active(
        target: request.target, skill: skill, startedAt: request.startedAt,
        statusDetail: session.initialStatusDetail), for: id)
    onEmitEvent?(id, WorkspaceEvent(skill.eventKind, at: request.startedAt))
    session.start()
  }

  @discardableResult
  func recordStash(
    items: [String], for id: String, companionName: String,
    currentTarget: WindowTargetCandidate?
  ) -> UUID? {
    guard let contents = StashContents(items) else { return nil }
    let target = binding(for: id).boundTarget ?? currentTarget
    let record = SessionRecord(
      kind: .stash,
      origin: .init(
        characterID: id, characterName: companionName,
        source: .init(
          appName: target?.appName ?? "Pocket Stash", bundleIdentifier: target?.bundleIdentifier,
          windowTitle: target?.windowTitle)),
      content: .init(
        text: .init(stashedItems: contents.items), notes: .init(summary: contents.summary),
        processing: .init(summaryPending: true)))
    vault.add(record)
    onEmitEvent?(id, WorkspaceEvent(.stashReceived, at: ProcessInfo.processInfo.systemUptime))
    if case .active = binding(for: id) { return record.id }
    let token = advanceBindingToken(for: id)
    vault.whenPersisted { [weak self] error in
      guard let self, self.sessions[id] == nil, self.bindingTokens[id] == token else { return }
      self.advanceBindingToken(for: id)
      self.setBinding(
        .completed(
          target: target, skill: .stash,
          summary: error == nil ? "Saved · View or Undo" : "Could not save · Open Vault",
          recordID: record.id,
          expiresAt: ProcessInfo.processInfo.systemUptime + Self.completionBannerDuration), for: id)
    }
    return record.id
  }

  func stopSkill(for id: String) { finishSession(for: id) }

  func unbind(companionID: String) {
    finishOrCancelSession(for: companionID)
    advanceBindingToken(for: companionID)
    setBinding(.followingFocusedWindow, for: companionID)
  }

  func stopAll() {
    for id in Array(Set(bindings.keys).union(sessions.keys).union(bindingTokens.keys)) {
      finishOrCancelSession(for: id)
      advanceBindingToken(for: id)
      onBindingChanged?(id, .followingFocusedWindow)
    }
    bindings.removeAll()
    stopClock()
  }

  func shutdown() async {
    await withCheckedContinuation { continuation in
      flushForTermination { continuation.resume() }
    }
  }

  func flushForTermination(completion: @escaping @Sendable () -> Void) {
    stopAll()
    vault.cancelPendingSummaries()
    whenFinished { [self] in
      vault.cancelPendingSummaries()
      vault.flushOnIOQueue(completion: completion)
    }
  }

  private func whenFinished(_ completion: @escaping () -> Void) {
    if finishingSessions.isEmpty { completion() } else { finishWaiters.append(completion) }
  }

  func drainPreviewsForTermination() { vault.drainStagedPreviewsForTermination() }
  func pollBoundWindows() { tick() }
  func refreshBoundWindows() { if !bindings.isEmpty { tick() } }
  func resumePendingSummaries() { vault.resumePendingSummaries() }
  func flushPendingSummaries() async { await vault.flushPendingSummaries() }

  @discardableResult
  private func advanceBindingToken(for id: String) -> UInt64 {
    nextBindingToken &+= 1
    bindingTokens[id] = nextBindingToken
    return nextBindingToken
  }

  private func makeSession(_ request: SessionRequest) -> (any ActiveSkillSession)? {
    switch request.skill {
    case .snap, .explain:
      guard let target = request.target else { return nil }
      return SnapSkillSession(
        request: .init(
          kind: request.skill, companionID: request.companionID,
          companionName: request.companionName, target: target)
      ) { [weak self] outcome in
        guard let self, self.bindingTokens[request.companionID] == request.token else { return }
        self.sessions.removeValue(forKey: request.companionID)
        self.save(outcome, request: request)
      }
    case .listen, .participate, .record:
      return makeAudioSession(request)
    case .watch:
      return request.target.map { WatchSkillSession(target: $0) }
    case .focus:
      return request.target.map { FocusSkillSession(target: $0, startedAt: request.startedAt) }
    case .stash: return nil
    }
  }

  private func makeAudioSession(_ request: SessionRequest) -> AudioSkillSession {
    let id = request.companionID
    let session = AudioSkillSession(
      request: .init(
        kind: request.skill, target: request.target,
        recordingDirectory: vault.storageDirectory), captureFactory: audioFactory,
      languages: audioLanguages
    ) { [weak self] in
      guard let self, self.bindingTokens[id] == request.token,
        let presentation = self.audioPresentation(for: id),
        case .active(let target, let skill, let startedAt, _, _) = self.binding(for: id)
      else { return }
      self.setBinding(
        .active(
          target: target, skill: skill, startedAt: startedAt,
          statusDetail: presentation.statusLine, audioLevel: presentation.audioLevel), for: id)
    }
    session.presentation.onFinish = { [weak self] in self?.stopSkill(for: id) }
    session.presentation.onOpenRecord = { [weak self] in self?.onOpenVaultRecord?($0) }
    return session
  }

  private func finishOrCancelSession(for id: String) {
    guard case .active(_, let skill, _, _, _) = binding(for: id), skill.savesPartialOnCancel else {
      sessions.removeValue(forKey: id)?.cancel()
      return
    }
    finishSession(for: id)
  }

  private func finishSession(for id: String) {
    guard let session = sessions.removeValue(forKey: id),
      case .active(let target, let skill, let startedAt, _, _) = binding(for: id)
    else { return }
    let request = SessionRequest(
      skill: skill, companionID: id,
      companionName: companionNames[id] ?? id.capitalized, target: target, startedAt: startedAt,
      token: bindingTokens[id] ?? 0)
    let finishID = UUID()
    finishingSessions[finishID] = session
    let context = SkillFinalizeContext(
      now: ProcessInfo.processInfo.systemUptime, startedAt: startedAt,
      companionID: id, companionName: request.companionName, target: target)
    setBinding(
      .active(target: target, skill: skill, startedAt: startedAt, statusDetail: "Finishing…"),
      for: id)
    session.finish(context) { [weak self] outcome in
      guard let self else { return }
      if let outcome {
        self.save(outcome, request: request)
      } else if self.bindingTokens[id] == request.token {
        self.setBinding(.followingFocusedWindow, for: id)
      }
      self.finishingSessions.removeValue(forKey: finishID)
      if self.finishingSessions.isEmpty {
        let completions = self.finishWaiters
        self.finishWaiters.removeAll()
        for completion in completions { completion() }
      }
    }
  }

  private func save(_ outcome: SkillCompletionOutcome, request: SessionRequest) {
    vault.add(outcome.record, image: outcome.image, pngData: outcome.pngData)
    vault.whenPersisted { [weak self] error in
      guard let self, self.bindingTokens[request.companionID] == request.token else { return }
      self.advanceBindingToken(for: request.companionID)
      let now = ProcessInfo.processInfo.systemUptime
      self.onEmitEvent?(request.companionID, WorkspaceEvent(.skillCompleted, at: now))
      self.setBinding(
        .completed(
          target: request.target, skill: request.skill,
          summary: error == nil ? outcome.bannerSummary : "Could not save · Open Vault",
          recordID: outcome.record.id, expiresAt: now + Self.completionBannerDuration),
        for: request.companionID)
    }
  }

  private func setBinding(_ state: CompanionBindingState, for id: String) {
    guard binding(for: id) != state else { return }
    if case .followingFocusedWindow = state {
      bindings.removeValue(forKey: id)
    } else {
      bindings[id] = state
    }
    updateClock()
    onBindingChanged?(id, state)
  }

  private func stopClock() {
    tickTask?.cancel()
    tickTask = nil
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func updateClock() {
    guard !bindings.isEmpty else {
      stopClock()
      return
    }
    guard tickTimer == nil else { return }
    let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = Self.tickTolerance
    RunLoop.main.add(timer, forMode: .common)
    tickTimer = timer
  }

  private func tick() {
    guard tickTask == nil, !bindings.isEmpty else { return }
    let requests = bindings.mapValues { TickRequest(token: 0, windowID: $0.boundTarget?.windowID) }
      .map { id, request in
        (id, TickRequest(token: bindingTokens[id] ?? 0, windowID: request.windowID))
      }
    let context = Dictionary(uniqueKeysWithValues: requests)
    let ids = Set(context.values.compactMap(\.windowID))
    if ids.isEmpty {
      applySnapshots([:], requests: context)
      return
    }
    let top = Double(NSScreen.screens.first?.frame.maxY ?? 0)
    let loader = snapshotLoader
    tickTask = Task { [weak self] in
      let snapshots = await loader(ids, top)
      guard !Task.isCancelled, let self else { return }
      self.tickTask = nil
      self.applySnapshots(snapshots, requests: context)
    }
  }

  private func applySnapshots(
    _ snapshots: [CGWindowID: WindowTargetSnapshot], requests: [String: TickRequest]
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var needsFollowup = false
    for (id, state) in bindings {
      guard let request = requests[id], request.token == bindingTokens[id],
        request.windowID == state.boundTarget?.windowID
      else {
        needsFollowup = true
        continue
      }
      switch state {
      case .followingFocusedWindow: break
      case .completed(var target, let skill, let summary, let recordID, let expires):
        guard now < expires else {
          setBinding(.followingFocusedWindow, for: id)
          continue
        }
        target = updatedTarget(target, snapshots: snapshots)
        setBinding(
          .completed(
            target: target, skill: skill, summary: summary, recordID: recordID, expiresAt: expires),
          for: id)
      case .active(var target, let skill, let start, let detail, let level):
        guard let session = sessions[id] else { continue }
        let snapshot = target.flatMap { snapshots[$0.windowID] }
        target = updatedTarget(target, snapshots: snapshots)
        let context = SkillTickContext(
          now: now, startedAt: start, currentDetail: detail,
          currentAudioLevel: level, target: target, snapshot: snapshot, frontmostPID: frontmost)
        switch session.tick(context) {
        case .completeNow: finishSession(for: id)
        case .keepRunning(let detail, let level):
          setBinding(
            .active(
              target: target, skill: skill, startedAt: start, statusDetail: detail,
              audioLevel: level), for: id)
        }
      }
    }
    updateClock()
    if needsFollowup { tick() }
  }

  private func updatedTarget(
    _ target: WindowTargetCandidate?, snapshots: [CGWindowID: WindowTargetSnapshot]
  ) -> WindowTargetCandidate? {
    guard var target else { return nil }
    if let snapshot = snapshots[target.windowID] { return snapshot.updating(target) }
    target.isVisible = false
    return target
  }
}
