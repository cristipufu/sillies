import AppKit
import Foundation
import Observation
import SilliesAudio
import SilliesChat
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
  var savedRecordCount: Int { vault.recordCount }
  var onBindingChanged: ((String, CompanionBindingState) -> Void)?
  var onEmitEvent: ((String, WorkspaceEvent) -> Void)?
  var onOpenVaultRecord: ((UUID) -> Void)?
  var onOpenAudioSession: ((AudioSessionPresentation) -> Void)?
  var onCloseChatSession: ((ChatSession) -> Void)?
  var onOpenChatSession: ((ChatSession) -> Void)?
  var onOpenChatSettings: ((ChatNotice.SettingsDestination) -> Void)?
  var makeChatSession: ((String, String) -> ChatSession?)?
  var canStartAudio: () -> Bool = { true }
  @ObservationIgnored var isAudioReserved: () -> Bool = { false }
  private var sessions: [String: any ActiveSkillSession] = [:]
  private var bindings: [String: CompanionBindingState] = [:]
  private var bindingTokens: [String: UInt64] = [:]
  private var pendingConversation = UUID()
  private var nextBindingToken: UInt64 = 0
  private var companionNames: [String: String] = [:]
  @ObservationIgnored private let audio: AudioSkillServices
  @ObservationIgnored private let snapshotLoader: SnapshotLoader
  private var finishingSessions: [UUID: any ActiveSkillSession] = [:]
  @ObservationIgnored private var finishWaiters: [() -> Void] = []
  @ObservationIgnored private var tickTimer: Timer?
  @ObservationIgnored private var tickTask: Task<Void, Never>?

  init(
    vault: SessionVaultStore, audio: AudioSkillServices,
    snapshotLoader: @escaping SnapshotLoader = { ids, top in
      await WindowTargetMetadata.shared.snapshots(for: ids, primaryScreenTop: top)
    }
  ) {
    self.audio = audio
    self.vault = vault
    self.snapshotLoader = snapshotLoader
    vault.resumePendingSummaries()
  }

  var activeAudioSession: AudioSessionPresentation? {
    (Array(sessions.values) + Array(finishingSessions.values)).compactMap {
      ($0 as? AudioSkillSession)?.presentation
    }.first
  }

  var activeChatSession: ChatSession? {
    (Array(sessions.values) + Array(finishingSessions.values)).compactMap {
      ($0 as? ConversationActivity)?.presentation
    }.first
  }

  var hasActiveCaptureSkill: Bool { activeAudioSession != nil || activeChatSession != nil }

  func audioPresentation(for id: String) -> AudioSessionPresentation? {
    (sessions[id] as? AudioSkillSession)?.presentation
  }

  func binding(for id: String) -> CompanionBindingState { bindings[id] ?? .followingFocusedWindow }

  func presentation(for id: String) -> SkillPresentation {
    let completed: SessionRecordHeader?
    if case .completed(_, _, _, let recordID, _) = binding(for: id) {
      completed = vault.records.first { $0.id == recordID }
    } else {
      completed = nil
    }
    return SkillPresentation(
      persistenceError: vault.persistenceError, completedRecord: completed,
      audioSession: audioPresentation(for: id),
      conversation: (sessions[id] as? ConversationActivity)?.presentation,
      speakingLevel: (sessions[id] as? ConversationActivity)?.presentation.phase == .speaking
        ? (sessions[id] as? ConversationActivity)?.presentation.audioLevel ?? 0 : 0)
  }

  func openSession(for id: String) {
    if let session = (sessions[id] as? ConversationActivity)?.presentation {
      onOpenChatSession?(session)
    } else if let session = audioPresentation(for: id) {
      onOpenAudioSession?(session)
    }
  }

  func openActiveSession() {
    if let session = activeChatSession {
      onOpenChatSession?(session)
    } else if let session = activeAudioSession {
      onOpenAudioSession?(session)
    }
  }

  func removeRecord(id: UUID) { vault.remove(id: id) }
  func whenPersisted(_ completion: @escaping @MainActor @Sendable (String?) -> Void) {
    vault.whenPersisted(completion)
  }

  func startSkill(
    _ skill: CompanionSkillKind, for id: String, companionName: String,
    target: WindowTargetCandidate? = nil
  ) {
    if skill == .chat {
      startConversation(.chat, for: id, name: companionName)
    } else {
      activateSkill(skill, for: id, companionName: companionName, target: target)
    }
  }

  @discardableResult
  private func activateSkill(
    _ skill: CompanionSkillKind, for id: String, companionName: String,
    target: WindowTargetCandidate? = nil
  ) -> (any ActiveSkillSession)? {
    guard !skill.requiresWindow || target != nil else { return nil }
    if skill == .chat, let existing = sessions[id] as? ConversationActivity {
      return existing
    }
    // One audio session prevents duplicate system/microphone taps across the whole crew.
    if skill.keepsCompanionStill,
      hasActiveCaptureSkill || isAudioReserved() || !canStartAudio()
    {
      return nil
    }
    finishOrCancelSession(for: id)
    companionNames[id] = companionName
    let request = SessionRequest(
      skill: skill, companionID: id, companionName: companionName,
      target: skill.requiresWindow ? target : nil, startedAt: ProcessInfo.processInfo.systemUptime,
      token: advanceBindingToken(for: id))
    guard let session = makeSession(request) else { return nil }
    sessions[id] = session
    setBinding(
      .active(
        target: request.target, skill: skill, startedAt: request.startedAt,
        statusDetail: session.initialStatusDetail), for: id)
    onEmitEvent?(id, WorkspaceEvent(skill.eventKind, at: request.startedAt))
    session.start()
    return session
  }

  @discardableResult
  func startConversation(
    _ mode: ConversationMode, for id: String, name: String, selectedRecord: UUID? = nil
  ) -> SessionFailure? {
    if selectedRecord != nil, let session = activeChatSession, session.companionID == id,
      session.phase != .loading || session.history.isLoaded, !session.canCompose
    {
      return .init(
        category: .captureUnavailable,
        message: String(
          localized: "Wait for the current reply or stop Talk before adding a Vault item."))
    }
    guard activeAudioSession == nil, !isAudioReserved(), canStartAudio() else {
      return .init(
        category: .captureUnavailable,
        message: String(localized: "Finish the active session before opening a conversation."))
    }
    let token = UUID()
    pendingConversation = token
    if let previous = activeChatSession, previous.companionID != id {
      stopSkill(for: previous.companionID)
      whenFinished { [weak self] in
        guard let self, self.pendingConversation == token else { return }
        self.startConversation(mode, for: id, name: name, selectedRecord: selectedRecord)
      }
      return nil
    }
    guard
      let conversation = activateSkill(.chat, for: id, companionName: name) as? ConversationActivity
    else {
      return .init(
        category: .captureUnavailable,
        message: String(
          localized: "This companion could not open a conversation. Please try again."))
    }
    let presentation = conversation.presentation
    switch mode {
    case .chat:
      presentation.showChat()
      onOpenChatSession?(presentation)
      if let selectedRecord {
        Task { [weak self, weak presentation] in
          guard let presentation else { return }
          await presentation.restoreHistory()
          guard let self, self.pendingConversation == token,
            self.sessions[id] === conversation
          else { return }
          presentation.selectedRecords.add(selectedRecord)
        }
      }
    case .talk:
      Task { [weak self, weak presentation] in
        guard let self, let presentation, self.pendingConversation == token,
          self.sessions[id] === conversation
        else { return }
        await presentation.startTalk()
      }
    }
    return nil
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
          appName: target?.appName ?? String(localized: "Pocket Stash"),
          bundleIdentifier: target?.bundleIdentifier,
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
          summary: error == nil
            ? String(localized: "Saved · View or Undo")
            : String(localized: "Could not save · Open Vault"),
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
    pendingConversation = UUID()
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
    vault.suspendBackgroundProcessing()
    whenFinished { [self] in
      vault.suspendBackgroundProcessing()
      vault.flushOnIOQueue(completion: completion)
    }
  }

  private func whenFinished(_ completion: @escaping () -> Void) {
    if finishingSessions.isEmpty { completion() } else { finishWaiters.append(completion) }
  }

  func drainPreviewsForTermination() { vault.drainStagedPreviewsForTermination() }
  func pollBoundWindows() { tick() }
  func refreshBoundWindows() { if !bindings.isEmpty { tick() } }
  func resumePendingSummaries() { vault.resumeBackgroundProcessing() }
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
        self.save(outcome, request: request, completionTarget: request.target)
      }
    case .listen, .participate, .record:
      return makeAudioSession(request)
    case .watch:
      return request.target.map { WatchSkillSession(target: $0) }
    case .focus:
      return request.target.map { FocusSkillSession(target: $0, startedAt: request.startedAt) }
    case .chat:
      guard let presentation = makeChatSession?(request.companionID, request.companionName) else {
        return nil
      }
      presentation.onFinish = { [weak self] in self?.stopSkill(for: request.companionID) }
      presentation.onChange = { [weak self, weak presentation] in
        guard let self, let presentation, self.bindingTokens[request.companionID] == request.token
        else { return }
        let state = CompanionBindingState.active(
          target: nil, skill: .chat, startedAt: request.startedAt,
          statusDetail: presentation.status, audioLevel: presentation.audioLevel)
        if self.binding(for: request.companionID) == state {
          // Notices and available controls can change without changing the status line.
          self.onBindingChanged?(request.companionID, state)
        } else {
          self.setBinding(state, for: request.companionID)
        }
      }
      return ConversationActivity(presentation: presentation)
    case .stash: return nil
    }
  }

  private func makeAudioSession(_ request: SessionRequest) -> AudioSkillSession {
    let id = request.companionID
    let session = AudioSkillSession(
      request: .init(
        kind: request.skill, target: request.target,
        recordingDirectory: vault.storageDirectory), services: audio
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
    finishSession(for: id, completionTarget: binding(for: id).boundTarget)
  }

  private func finishSession(for id: String, completionTarget: WindowTargetCandidate?) {
    guard let session = sessions.removeValue(forKey: id),
      case .active(let target, let skill, let startedAt, _, _) = binding(for: id)
    else { return }
    if let conversation = session as? ConversationActivity {
      onCloseChatSession?(conversation.presentation)
    }
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
      .active(
        target: completionTarget, skill: skill, startedAt: startedAt,
        statusDetail: String(localized: "Finishing…")),
      for: id)
    session.finish(context) { [weak self] outcome in
      guard let self else { return }
      if let outcome {
        self.save(outcome, request: request, completionTarget: completionTarget)
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

  private func save(
    _ outcome: SkillCompletionOutcome, request: SessionRequest,
    completionTarget: WindowTargetCandidate?
  ) {
    vault.add(outcome.record, image: outcome.image, pngData: outcome.pngData)
    vault.whenPersisted { [weak self] error in
      guard let self, self.bindingTokens[request.companionID] == request.token else { return }
      self.advanceBindingToken(for: request.companionID)
      let now = ProcessInfo.processInfo.systemUptime
      self.onEmitEvent?(request.companionID, WorkspaceEvent(.skillCompleted, at: now))
      self.setBinding(
        .completed(
          target: completionTarget, skill: request.skill,
          summary: error == nil
            ? outcome.bannerSummary : String(localized: "Could not save · Open Vault"),
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
        if let target, snapshot?.hasClosed(target) == true {
          finishSession(for: id, completionTarget: nil)
          continue
        }
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
    if let snapshot = snapshots[target.windowID] {
      return snapshot.hasClosed(target) ? nil : snapshot.updating(target)
    }
    target.isVisible = false
    return target
  }
}
