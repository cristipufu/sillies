import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import SilliesTTS

/// Owns conversation turns; capture, reasoning, synthesis and hardware playback are injected ports.
@MainActor @Observable
package final class ChatSession {
  package enum Phase: String, Sendable {
    case loading, ready, preparingMicrophone, listening, finalizing, thinking, preparingVoice,
      speaking,
      finished
  }
  package let companionName: String
  package let companionID: String
  package private(set) var profile: CharacterChatProfile
  private var languageOverride: String?
  private struct ProfileUpdate {
    let profile: CharacterChatProfile
    let languageOverride: String?
  }
  @ObservationIgnored private var pendingProfile: ProfileUpdate?
  package let history: ChatHistory
  package let browser: ConversationBrowser
  package let export: ConversationExport
  package let memoryEditor: ChatMemoryEditor
  package let selectedRecords: ChatSelectedRecords
  package let personalFacts: ChatPersonalFacts
  private let historyMutation = ChatPersistenceOperation<ConversationSnapshot>()
  package private(set) var mode = ConversationMode.chat
  package private(set) var messages: [ChatMessage] = []
  package private(set) var hasEarlierMessages = false
  package private(set) var streamedText = ""
  @ObservationIgnored private var streamingMessageID: UUID?
  package private(set) var phase = Phase.ready
  package private(set) var failure: SessionFailure?
  package private(set) var notice: ChatNotice?
  package private(set) var readiness = ChatReadiness.unchecked
  @ObservationIgnored private var readinessGeneration = UUID()
  package private(set) var audioLevel = 0.0
  package var draft = "" { didSet { saveCheckpoint() } }
  package var language: String { didSet { saveCheckpoint() } }
  package var spokenReplies = true
  package private(set) var isVoiceConversationActive = false
  private var isFinalizingMicrophone = false
  private var isReceivingSpeech = false
  package private(set) var discoveredSources: [ChatSource] = []
  private var sourceCardOwners: [UUID: UUID] = [:]
  @ObservationIgnored private var memory = ConversationMemory()
  @ObservationIgnored private var isRestoringHistory = false
  @ObservationIgnored private var voiceDraft: String?
  @ObservationIgnored private var voiceActivation = UUID()
  private static let maximumLoadedMessages = ConversationPageRequest.maximumLimit
  private var toolActivity: String?
  package var onChange: (@MainActor () -> Void)?
  package var onFinish: (@MainActor () -> Void)?
  @ObservationIgnored private let services: ChatServices
  @ObservationIgnored private let diagnostics: ChatDiagnostics
  @ObservationIgnored private let microphone: ChatMicrophone
  @ObservationIgnored private let voiceInterruption: ChatVoiceInterruption
  @ObservationIgnored private var restoration: Task<Void, Never>?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var speechDrain: Task<Void, Never>?
  @ObservationIgnored private var turnID = UUID()
  @ObservationIgnored private var speechID = UUID()
  @ObservationIgnored private var replySpeechProfile: CharacterChatProfile?
  @ObservationIgnored private var replayMessageID: UUID?
  @ObservationIgnored private var pendingVoiceTurns: [Int: String] = [:]
  @ObservationIgnored private var voiceFinalizations = 0
  @ObservationIgnored private var voiceSequence = 0
  @ObservationIgnored private var spokenDelivery: ChatTurnDelivery?
  @ObservationIgnored private var voiceTurnEndedAt: ContinuousClock.Instant?
  @ObservationIgnored private var voiceEndpoint: VoiceEndpointTiming?
  @ObservationIgnored private var replyHasSpeech = false
  @ObservationIgnored private var conversationLifetime = SpeechModelLifetime()
  package var firstTextLatency: Duration? { spokenDelivery?.snapshot.firstText }
  package var firstAudioLatency: Duration? { spokenDelivery?.snapshot.firstAudio }
  package var firstPCMLatency: Duration? { spokenDelivery?.snapshot.firstPCM }
  package var voicePreparedLatency: Duration? { spokenDelivery?.snapshot.voicePrepared }
  package var endpointLatency: Duration? { spokenDelivery?.snapshot.endpoint }
  package var recognitionFinalizedLatency: Duration? {
    spokenDelivery?.snapshot.recognitionFinalized
  }

  package init(
    companionName: String, profile: CharacterChatProfile, services: ChatServices,
    companionID: String = "", languageOverride: String? = nil
  ) {
    self.companionName = companionName
    self.companionID = companionID
    self.profile = profile
    self.languageOverride = languageOverride
    language = languageOverride ?? profile.languageIdentifier
    self.services = services
    diagnostics = ChatDiagnostics(sink: services.diagnostics)
    let history = ChatHistory(configuration: services.history)
    self.history = history
    export = ConversationExport(
      history: history, companionName: companionName, deliver: services.deliver)
    memoryEditor = ChatMemoryEditor(history: history)
    selectedRecords = ChatSelectedRecords(provider: services.context.materials)
    personalFacts = ChatPersonalFacts(history: history, repository: services.context.personalFacts)
    browser = ConversationBrowser(history: history)
    microphone = ChatMicrophone(services: services)
    voiceInterruption = ChatVoiceInterruption(output: services.speech)
    memoryEditor.allowsCorrection = { [weak self] in self?.canCompose == true }
    selectedRecords.canChange = { [weak self] in self?.canCompose == true }
    selectedRecords.onChange = { [weak self] in self?.saveCheckpoint() }
    personalFacts.canChange = { [weak self] in self?.canCompose == true }
    memoryEditor.onCorrection = { [weak self] snapshot in
      guard let self, self.phase != .finished else { return }
      self.restore(snapshot)
    }
    if !history.isLoaded { phase = .loading }
  }

  deinit { Task { [conversationLifetime] in await conversationLifetime.end() } }

  package var isRecording: Bool { phase == .preparingMicrophone || phase == .listening }
  package var isWorking: Bool {
    voiceInterruption.isActive || [.thinking, .preparingVoice, .speaking].contains(phase)
  }
  package var canCompose: Bool {
    phase == .ready && !isFinalizingMicrophone && history.isLoaded && history.failure == nil
      && !memoryEditor.isSaving && !personalFacts.isSaving
  }
  package var canSend: Bool {
    canCompose && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.count <= ChatContext.maximumMessageCharacters
  }
  package var canRetry: Bool {
    canCompose && (messages.last?.role == .user || messages.last?.completion == .interrupted)
  }
  package var pendingClarification: ChatClarification? {
    guard let question = messages.last?.clarification, question.resolution == .pending else {
      return nil
    }
    return question
  }
  package var canAnswerClarification: Bool {
    canCompose
      || (phase == .listening && isVoiceConversationActive && !isReceivingSpeech
        && draft.isEmpty && !isFinalizingMicrophone && voiceFinalizations == 0
        && history.failure == nil && !memoryEditor.isSaving)
  }

  package func answerClarification(_ id: UUID, choice: String) {
    guard canAnswerClarification, let question = pendingClarification, question.id == id,
      question.choices.contains(choice)
    else { return }
    // Choosing a card never overwrites a draft the user was already composing.
    if phase == .listening { setPhase(.ready) }
    submit(choice)
  }

  package func dismissClarification(_ id: UUID) {
    guard pendingClarification?.id == id else { return }
    resolveClarification(.cancelled)
  }

  private func resolveClarification(_ resolution: ChatClarification.Resolution) {
    guard let question = pendingClarification, let index = messages.indices.last else { return }
    messages[index] = messages[index].asking(question.resolving(resolution))
    history.stage(messages[index])
  }
  package var canContinueSpeaking: Bool {
    mode == .talk && !isWorking && !isFinalizingMicrophone && voiceFinalizations == 0
      && !isReceivingSpeech && (phase != .listening || draft.isEmpty)
      && (phase == .ready || phase == .listening)
      && messages.last.flatMap(SpokenReplyContinuation.init) != nil
  }

  package func continueSpeaking() {
    guard canContinueSpeaking, let message = messages.last,
      let continuation = SpokenReplyContinuation(message)
    else { return }
    let phrases = SpokenTextChunks.split(
      continuation.remainingText, maximumCharacters: SpokenPhraseBuffer.maximumPhraseCharacters)
    var speech = SpokenReplyProgress()
    if !continuation.completedText.isEmpty {
      speech.append(continuation.completedText)
      speech.completed(continuation.completedText)
    }
    for phrase in phrases { speech.append(phrase) }
    guard !speech.remainingPhrases.isEmpty else { return }
    turnID = UUID()
    replayMessageID = continuation.messageID
    replySpeechProfile = CharacterChatProfile(
      personality: profile.personality, languageIdentifier: language,
      preferredVoices: profile.preferredVoices)
    spokenDelivery = ChatTurnDelivery(started: .now, speech: speech)
    diagnostics.record(.recoveryStarted, turn: turnID, reason: .explicitContinuation)
    failure = nil
    notice = nil
    replaySpeech()
  }
  package var recoverySettingsDestination: ChatNotice.SettingsDestination? {
    switch failure?.category {
    case .textGeneration: .textModels
    case .speechSynthesis: .voices
    case .transcription: .recognition
    default: notice?.settingsDestination
    }
  }
  package var transcript: String {
    ChatTranscript.render(messages.map { presentedMessage($0) }, companionName: companionName)
  }
  package var status: String {
    switch phase {
    case .loading: String(localized: "Loading conversation…")
    case .ready:
      if case .checking = readiness {
        String(localized: "Checking conversation setup…")
      } else {
        mode == .talk ? String(localized: "Start talking") : String(localized: "Ready to chat")
      }
    case .preparingMicrophone: String(localized: "Getting the microphone ready…")
    case .listening: String(localized: "Listening…")
    case .finalizing: String(localized: "Finishing your words…")
    case .thinking:
      toolActivity
        ?? (streamedText.isEmpty
          ? String(localized: "Thinking…") : String(localized: "Writing a reply…"))
    case .preparingVoice: String(localized: "Getting the voice ready…")
    case .speaking: String(localized: "Speaking…")
    case .finished: String(localized: "Chat finished")
    }
  }

  package func send() {
    guard canSend else { return }
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    submit(text)
  }

  @discardableResult
  package func useSuggestedDraft(_ text: String) -> Bool {
    guard canCompose, draft.isEmpty, text.count <= ChatContext.maximumMessageCharacters else {
      return false
    }
    resolveClarification(.superseded)
    draft = text
    return true
  }

  private func submit(_ text: String) {
    resolveClarification(.answered)
    messages.append(.init(role: .user, text: text))
    if let message = messages.last { history.stage(message) }
    requestReply()
  }

  package func retry() {
    guard canRetry else { return }
    if messages.last?.completion == .interrupted {
      history.remove(messages.removeLast().id)
    }
    rebuildSourceCardOwners()
    requestReply()
  }

  package func refreshAvailability() async {
    guard phase == .ready else { return }
    let requestedLanguage = language
    let requestedMode = mode
    let requestedTurn = turnID
    let generation = UUID()
    readinessGeneration = generation
    readiness = .checking
    defer {
      if readinessGeneration == generation, case .checking = readiness { readiness = .unchecked }
    }
    let result = await ChatReadiness.resolve(
      services: services, language: requestedLanguage, mode: requestedMode)
    guard !Task.isCancelled, phase == .ready, language == requestedLanguage,
      mode == requestedMode, turnID == requestedTurn, readinessGeneration == generation
    else { return }
    readiness = result
    notice = result.notice
    if case .permissionRequired(let permission) = result {
      failure = permission
    } else if failure?.category == .permissionDenied {
      failure = nil
    }
  }

  package func startListening() {
    guard canCompose, draft.isEmpty else { return }
    failure = nil
    isVoiceConversationActive = true
    setPhase(.preparingMicrophone)
    microphone.start(language: language) { [weak self] in self?.receiveCapture($0) }
  }

  package func finishListening() {
    guard phase == .listening, isVoiceConversationActive else { return }
    voiceTurnEndedAt = .now
    setPhase(.finalizing)
    let sequence = voiceSequence
    voiceSequence += 1
    voiceFinalizations += 1
    microphone.finishTurn { [weak self] result in
      self?.completeVoiceTurn(result, sequence: sequence)
    }
  }

  package func muteMicrophone() {
    guard isVoiceConversationActive else { return }
    if voiceInterruption.isActive { cancelReply(because: .microphoneMuted) }
    isVoiceConversationActive = false
    isFinalizingMicrophone = true
    clearVoiceTiming()
    if !isWorking { setPhase(.finalizing) }
    microphone.finish { [weak self] result in
      guard let self else { return }
      self.isFinalizingMicrophone = false
      guard self.phase != .finished else { return }
      self.preserveFinalWords(result)
      if !self.isWorking { self.setPhase(.ready) }
    }
  }

  package func stopVoiceConversation() {
    guard isVoiceConversationActive else { return }
    isVoiceConversationActive = false
    clearVoiceTiming()
    cancelReply(because: .voiceEnded)
    setPhase(.finalizing)
    microphone.finish { [weak self] result in
      guard let self, self.phase != .finished else { return }
      self.preserveFinalWords(result)
      self.setPhase(.ready)
    }
  }

  private func completeVoiceTurn(_ result: AudioCaptureResult?, sequence: Int) {
    voiceFinalizations -= 1
    if let result {
      let words = result.plainText.isEmpty ? result.transcript : result.plainText
      pendingVoiceTurns[sequence] = words
      if let failure = result.failure {
        diagnostics.failed(failure, area: .recognition, turn: turnID)
        self.failure = failure
        if isVoiceConversationActive { stopVoiceConversation() }
        return
      }
    }
    guard isVoiceConversationActive, phase == .finalizing, voiceFinalizations == 0 else { return }
    if pendingVoiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let resolution = voiceInterruption.resolveEmpty(turnID: turnID)
    {
      diagnostics.record(.emptyRecognition, turn: turnID, reason: .emptyRecognition)
      pendingVoiceTurns.removeAll()
      voiceSequence = 0
      draft = ""
      clearVoiceTiming()
      switch resolution {
      case .resume(let previous): setPhase(previous)
      case .recover: recoverSpeech()
      }
      return
    }
    if voiceInterruption.isActive { cancelReply(because: .recognizedWords) }
    draft = pendingVoiceText
    pendingVoiceTurns.removeAll()
    voiceSequence = 0
    setPhase(.ready)
    if canSend {
      send()
    } else if draft.isEmpty {
      clearVoiceTiming()
      setPhase(.listening)
    } else {
      stopVoiceConversation()
    }
  }

  package func interrupt() {
    guard isWorking else { return }
    cancelReply(because: .userStop)
    setPhase(isVoiceConversationActive ? .listening : .ready)
  }

  package func finish(completion: @escaping @MainActor () -> Void) {
    selectedRecords.stop()
    personalFacts.stop()
    export.cancel()
    browser.cancelSearch()
    browser.cancelNavigation()
    memoryEditor.close()
    voiceActivation = UUID()
    restoration?.cancel()
    Task { [conversationLifetime] in await conversationLifetime.end() }
    isVoiceConversationActive = false
    clearVoiceTiming()
    cancelReply(because: .sessionClosed)
    setPhase(.finished)
    microphone.finish { [self] result in
      isFinalizingMicrophone = false
      preserveFinalWords(result)
      saveCheckpoint()
      historyMutation.finish(deliver: services.deliver) { [self] in
        personalFacts.finish(deliver: services.deliver) { [self] in
          export.finish { [self] in
            history.stopAndFlush(deliver: services.deliver, completion: completion)
          }
        }
      }
    }
  }

  private func clearVoiceTiming() {
    isReceivingSpeech = false
    voiceTurnEndedAt = nil
    voiceEndpoint = nil
  }

  private func requestReply() {
    guard phase == .ready else { return }
    failure = nil
    notice = nil
    toolActivity = nil
    discoveredSources = []
    let token = UUID()
    turnID = token
    diagnostics.record(.started, turn: token)
    speechID = token
    let delivery = ChatTurnDelivery(started: voiceTurnEndedAt ?? .now, endpoint: voiceEndpoint)
    delivery.beginSpeech(token)
    spokenDelivery = delivery
    clearVoiceTiming()
    replyHasSpeech = spokenReplies
    let profile = CharacterChatProfile(
      personality: profile.personality, languageIdentifier: language,
      preferredVoices: profile.preferredVoices)
    replySpeechProfile = profile
    replayMessageID = nil
    let context = ChatContext(
      companionName: companionName, profile: profile, messages: messages, memory: memory
    ).inTurn(token, session: conversationLifetime.id).inHistory(history.handle).presented(as: mode)
      .selecting(selectedRecords.selection)
    setPhase(.thinking)
    operation = Task { [weak self, services, conversationLifetime, speechDrain] in
      do {
        await speechDrain?.value
        try Task.checkCancellation()
        try await self?.history.flush()
        try Task.checkCancellation()
        await services.conversation.retain(for: conversationLifetime)
        let turn = ChatTurnOperation(
          services: services,
          delivery: .init(
            progress: { [weak self] progress in
              services.deliver { [weak self] in self?.receive(progress, turn: token) }
            },
            text: { [weak self] text in
              delivery.receivedText()
              await self?.receiveText(text, turn: token)
            },
            textFinished: { [weak self] in
              await self?.waitingForVoice(turn: token)
            },
            playback: { [weak self] update in
              guard delivery.received(update, from: token) else { return }
              services.deliver { [weak self] in
                self?.receivePlayback(update, token: token, attempt: token)
              }
            }, plannedSpeech: delivery.plannedSpeech), voiceLifetime: conversationLifetime)
        let result = try await turn.run(
          context, output: self?.spokenReplies == true ? .spoken : .text)
        try Task.checkCancellation()
        guard let self, self.turnID == token else { return }
        self.completeReply(result.reply, turn: token)
        switch result.voice {
        case .finished: break
        case .preempted:
          self.diagnostics.record(.preempted, turn: token, reason: .runtimeCancellation)
          if self.isVoiceConversationActive {
            self.suspendSpokenReply()
            return
          }
          self.failure = SessionFailure(TTSError.interrupted, category: .speechSynthesis)
        case .notice(let message): self.notice = .voiceUnavailable(message)
        case .failed(let failure):
          self.diagnostics.failed(failure, area: .synthesis, turn: token)
          self.failure = failure
        }
        self.finishReplyActivity()
      } catch {
        guard let self, self.turnID == token, !Task.isCancelled else { return }
        self.markInterrupted(token)
        // Recognition can preempt inference before its speech-start update reaches the UI.
        if error is CancellationError {
          self.diagnostics.record(.preempted, turn: token, reason: .runtimeCancellation)
          if self.isVoiceConversationActive, self.replyHasSpeech {
            self.suspendSpokenReply()
            return
          }
          self.finishReplyActivity()
          return
        }
        self.voiceInterruption.cancel()
        self.diagnostics.failed(error, area: .chat, turn: token)
        self.failure = SessionFailure(
          error, category: .textGeneration)
        self.operation = nil
        if self.isVoiceConversationActive {
          self.stopVoiceConversation()
        } else {
          self.setPhase(.ready)
          await self.refreshAvailability()
        }
      }
    }
  }

  private func finishReplyActivity() {
    diagnostics.delivery(spokenDelivery?.snapshot, turn: turnID)
    diagnostics.record(.completed, turn: turnID)
    if let replayMessageID { saveSpokenProgress(for: replayMessageID) }
    operation = nil
    spokenDelivery?.endSpeech(speechID)
    voiceInterruption.cancel()
    // Capture owns its in-flight utterance. A reply completing or being preempted must not
    // replace finalization with listening and strand the final recognizer result.
    guard !isFinalizingMicrophone else { return }
    if isVoiceConversationActive, phase == .listening || phase == .finalizing { return }
    setPhase(isVoiceConversationActive ? .listening : .ready)
  }

  private func suspendSpokenReply() {
    operation = nil
    spokenDelivery?.endSpeech(speechID)
    guard spokenDelivery?.snapshot.speech.remainingPhrases.isEmpty == false else {
      finishReplyActivity()
      return
    }
    let canRecover = voiceInterruption.preempt(turnID: turnID, speechID: speechID, phase: phase)
    if phase != .finalizing, !isFinalizingMicrophone { setPhase(.listening) }
    if canRecover { recoverSpeech() }
  }

  private func recoverSpeech() {
    diagnostics.record(.recoveryStarted, turn: turnID, reason: .emptyRecognition)
    voiceInterruption.cancel()
    guard isVoiceConversationActive, let delivery = spokenDelivery,
      replySpeechProfile != nil,
      !delivery.snapshot.speech.remainingPhrases.isEmpty
    else {
      finishReplyActivity()
      if isVoiceConversationActive, voiceFinalizations == 0, !isFinalizingMicrophone {
        setPhase(.listening)
      }
      return
    }
    replaySpeech()
  }

  private func replaySpeech() {
    guard let delivery = spokenDelivery, let profile = replySpeechProfile else { return }
    let token = turnID
    let attempt = UUID()
    speechID = attempt
    diagnostics.speechAttempt(attempt, for: token)
    delivery.beginSpeech(attempt)
    let replay = ChatSpeechReplay(
      output: services.speech,
      request: .init(id: attempt, text: "", profile: profile, lifetime: conversationLifetime),
      phrases: delivery.snapshot.speech.remainingPhrases)
    setPhase(.preparingVoice)
    operation = Task { [weak self, services, speechDrain] in
      do {
        await speechDrain?.value
        try Task.checkCancellation()
        let notice = try await replay.run { [weak self] update in
          guard delivery.received(update, from: attempt) else { return }
          services.deliver { [weak self] in
            self?.receivePlayback(update, token: token, attempt: attempt)
          }
        }
        guard let self, self.turnID == token, self.speechID == attempt, !Task.isCancelled else {
          return
        }
        if let notice { self.notice = .voiceUnavailable(notice) }
        self.finishReplyActivity()
      } catch {
        guard let self, self.turnID == token, self.speechID == attempt, !Task.isCancelled else {
          return
        }
        if error is CancellationError {
          self.diagnostics.record(.preempted, turn: token, reason: .runtimeCancellation)
          if self.isVoiceConversationActive {
            self.suspendSpokenReply()
          } else {
            self.finishReplyActivity()
          }
        } else {
          self.diagnostics.failed(error, area: .synthesis, turn: token)
          self.failure = SessionFailure(error, category: .speechSynthesis)
          self.finishReplyActivity()
        }
      }
    }
  }

  package func presentedMessage(_ message: ChatMessage) -> ChatMessage {
    guard message.id == streamingMessageID else { return message }
    return message.withText(streamedText).withEvidence(
      .init(sources: discoveredSources, exchanges: message.exchanges))
  }

  package func sourceCards(for message: ChatMessage) -> [ChatSource] {
    presentedMessage(message).sources.filter { sourceCardOwners[$0.id] == message.id }
  }

  private func claimSourceCards(_ sources: [ChatSource], for messageID: UUID) {
    for source in sources where sourceCardOwners[source.id] == nil {
      sourceCardOwners[source.id] = messageID
    }
  }

  private func rebuildSourceCardOwners() {
    sourceCardOwners.removeAll(keepingCapacity: true)
    for message in messages { claimSourceCards(message.sources, for: message.id) }
  }

  private func waitingForVoice(turn: UUID) {
    guard turnID == turn, phase == .thinking else { return }
    toolActivity = nil
    setPhase(.preparingVoice)
  }

  private func receiveText(_ text: String, turn: UUID) {
    guard turnID == turn, isWorking else { return }
    if streamedText.isEmpty { diagnostics.delivery(spokenDelivery?.snapshot, turn: turn) }
    streamedText = text
    beginReplyPresentation(turn)
    if let message = messages.last { history.stage(presentedMessage(message)) }
    onChange?()
  }

  private func beginReplyPresentation(_ turn: UUID) {
    guard streamingMessageID != turn else { return }
    streamingMessageID = turn
    messages.append(
      ChatMessage(id: turn, role: .companion, text: "")
        .withDelivery(.streaming, spokenText: nil))
  }

  private func completeReply(_ reply: ChatReply, turn: UUID) {
    memory = reply.memory
    let message = ChatMessage(
      id: turn, role: .companion, text: reply.text,
      evidence: .init(sources: reply.sources, exchanges: reply.exchanges)
    )
    .inspecting(reply.contextInspection)
    .asking(reply.clarification)
    .withDelivery(.complete, spokenText: replyHasSpeech ? spokenDelivery?.snapshot.spokenText : nil)
    if let index = messages.firstIndex(where: { $0.id == turn }) {
      messages[index] = message
    } else {
      messages.append(message)
    }
    clearStreamPresentation()
    rebuildSourceCardOwners()
    discoveredSources = []
    toolActivity = nil
    history.stage(message)
    diagnostics.contextPrepared(
      reply.contextInspection, toolCalls: reply.exchanges.count, turn: turn)
    saveCheckpoint()
    if messages.count > Self.maximumLoadedMessages {
      messages.removeFirst(messages.count - Self.maximumLoadedMessages)
      hasEarlierMessages = history.handle != nil
      rebuildSourceCardOwners()
    }
  }

  private func markInterrupted(_ turn: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == turn }),
      messages[index].completion == .streaming
    else { return }
    messages[index] = presentedMessage(messages[index]).withDelivery(
      .interrupted, spokenText: replyHasSpeech ? spokenDelivery?.snapshot.spokenText : nil)
    clearStreamPresentation()
    history.stage(messages[index])
  }

  private func clearStreamPresentation() {
    streamingMessageID = nil
    streamedText = ""
  }

  private func receive(_ progress: ChatProgress, turn: UUID) {
    if case .remembered(let receipt) = progress {
      if history.handle == receipt.handle { history.receivedMemory(receipt) }
      return
    }
    guard turnID == turn, phase != .finished else { return }
    guard isWorking else {
      // Progress crosses an asynchronous UI delivery boundary. A search may finish before the
      // reply fails, yet its cards reach the UI after the failure has already been presented.
      if failure != nil, messages.last?.completion != .complete,
        case .sources(let sources) = progress
      {
        preserveSourcesAfterFailure(sources, turn: turn)
      }
      return
    }
    switch progress {
    case .remembered(let receipt): history.receivedMemory(receipt)
    case .waitingForInference: toolActivity = String(localized: "Waiting for local AI…")
    case .preparingContext: toolActivity = String(localized: "Preparing conversation…")
    case .generating: toolActivity = nil
    case .compacting: toolActivity = String(localized: "Remembering our conversation…")
    case .memory(let value):
      memory = value
      saveCheckpoint()
      toolActivity = nil
    case .usingTool(let activity): toolActivity = activity
    case .sources(let sources):
      discoveredSources = sources
      if sources.contains(where: { sourceCardOwners[$0.id] == nil }) {
        beginReplyPresentation(turn)
        claimSourceCards(sources, for: turn)
      }
    }
    onChange?()
  }

  private func preserveSourcesAfterFailure(_ sources: [ChatSource], turn: UUID) {
    discoveredSources = sources
    if let index = messages.firstIndex(where: { $0.id == turn }) {
      messages[index] = messages[index].withEvidence(
        .init(sources: sources, exchanges: messages[index].exchanges))
    } else if sources.contains(where: { sourceCardOwners[$0.id] == nil }) {
      messages.append(
        ChatMessage(
          id: turn, role: .companion, text: "",
          evidence: .init(sources: sources)
        ).withDelivery(.interrupted, spokenText: nil))
    }
    claimSourceCards(sources, for: turn)
    if let message = messages.first(where: { $0.id == turn }) { history.stage(message) }
    onChange?()
  }

  private func receiveCapture(_ update: AudioCaptureUpdate) {
    guard isVoiceConversationActive else { return }
    switch update {
    case .capturing: setPhase(.listening)
    case .speechStarted:
      diagnostics.record(.speechDetected, turn: turnID)
      clearVoiceTiming()
      isReceivingSpeech = true
      if isWorking {
        voiceInterruption.begin(turnID: turnID, speechID: speechID, phase: phase)
      } else {
        cancelReply(because: .speechDetected)
      }
      draft = ""
      setPhase(.listening)
    case .speechEnded(let timing):
      isReceivingSpeech = false
      diagnostics.record(.speechEnded, turn: turnID)
      guard phase == .listening else { return }
      voiceEndpoint = timing
      finishListening()
    case .transcript(let text, let level, _):
      guard phase == .listening else { return }
      if voiceInterruption.isActive, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        cancelReply(because: .recognizedWords)
      }
      draft = text
      audioLevel = level
      onChange?()
      if text.count >= ChatContext.maximumMessageCharacters {
        finishListening()
      }
    case .failed(let error), .transcriptionStopped(let error):
      diagnostics.failed(error, area: .recognition, turn: turnID)
      failure = error
      stopVoiceConversation()
    default: break
    }
  }

  private func receivePlayback(_ update: SpeechPlaybackUpdate, token: UUID, attempt: UUID) {
    guard turnID == token, speechID == attempt, phase != .finished else { return }
    switch update {
    case .milestone:
      diagnostics.delivery(spokenDelivery?.snapshot, turn: token)
      return
    case .speaking(let level):
      guard isWorking else { return }
      guard !voiceInterruption.isActive else { return }
      phase = .speaking
      diagnostics.phaseChanged(.speaking, turn: token)
      audioLevel = level
    case .finished, .interrupted: audioLevel = 0
    case .utteranceFinished:
      saveSpokenProgress(for: replayMessageID ?? token)
    }
    onChange?()
  }

  private func saveSpokenProgress(for messageID: UUID) {
    guard streamingMessageID != messageID,
      let index = messages.firstIndex(where: { $0.id == messageID })
    else { return }
    let message = messages[index]
    messages[index] = message.withDelivery(
      message.completion ?? .complete, spokenText: spokenDelivery?.snapshot.spokenText)
    history.stage(messages[index])
  }

  private func preserveFinalWords(_ result: AudioCaptureResult?) {
    let unfinished = result.map { $0.plainText.isEmpty ? $0.transcript : $0.plainText } ?? ""
    let text = [pendingVoiceText, unfinished].filter { !$0.isEmpty }.joined(separator: " ")
    if !text.isEmpty { draft = text }
    if let failure = result?.failure { self.failure = failure }
    pendingVoiceTurns.removeAll()
    voiceFinalizations = 0
    voiceSequence = 0
    if let typedDraft = voiceDraft {
      if !text.isEmpty {
        let message = ChatMessage(role: .user, text: text)
        messages.append(message)
        history.stage(message)
      }
      draft = typedDraft
      voiceDraft = nil
      saveCheckpoint()
    }
  }

  package func restoreHistory() async {
    if let restoration {
      await restoration.value
      return
    }
    guard !history.isLoaded, phase != .finished else { return }
    setPhase(.loading)
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        if let snapshot = try await history.load(.init(id: companionID, name: companionName)) {
          guard !Task.isCancelled, phase != .finished else { return }
          restore(snapshot)
          if let id = snapshot.checkpoint.readingMessageID { await browser.show(.around(id)) }
        }
      } catch {
        // The load failure stays visible.
      }
      guard phase != .finished else { return }
      setPhase(.ready)
    }
    restoration = task
    await task.value
    restoration = nil
  }

  package func restore(_ snapshot: ConversationSnapshot) {
    isRestoringHistory = true
    history.restore(snapshot)
    browser.reset()
    messages = snapshot.page.entries.map(\.message)
    hasEarlierMessages = snapshot.page.hasOlder
    memory = snapshot.checkpoint.memory
    selectedRecords.restore(snapshot.checkpoint.selectedRecords)
    draft = snapshot.checkpoint.draft
    language = languageOverride ?? snapshot.checkpoint.language ?? profile.languageIdentifier
    rebuildSourceCardOwners()
    isRestoringHistory = false
  }

  package func retrySaving() async {
    if !history.isLoaded {
      await restoreHistory()
      return
    }
    do { try await history.flush() } catch {  // ChatHistory keeps the failed payload and notice.
    }
  }

  package func undoMemory(_ receipt: MemoryReceipt) async {
    await changeMemories { repository, handle in
      try await repository.undoMemory(handle, receiptID: receipt.id)
    }
  }

  package func forgetMemory(_ fact: CompanionMemory) async {
    await changeMemories { repository, handle in
      try await repository.forget(handle, id: fact.id)
    }
  }

  private func changeMemories(
    _ change:
      @escaping @Sendable (any CompanionMemoryRepository, ConversationHandle) async throws ->
      ConversationSnapshot
  ) async {
    guard canCompose, let repository = history.configuration.memories, let handle = history.handle
    else { return }
    await mutateHistory { try await change(repository, handle) }
  }

  package func clearConversation() async {
    await removeConversationData(.messagesAndMemories)
  }

  package func removeConversationData(_ removal: ConversationDataRemoval) async {
    guard canCompose, let repository = history.configuration.conversations,
      let handle = history.handle
    else { return }
    await mutateHistory {
      if let manager = repository as? any ConversationDataManaging {
        return try await manager.removeConversationData(removal, handle: handle)
      } else if removal == .messagesAndMemories {
        return try await repository.clear(handle)
      } else {
        throw ConversationStorageError.invalidData
      }
    }
  }

  private func mutateHistory(
    _ mutation: @escaping @Sendable () async throws -> ConversationSnapshot
  ) async {
    setPhase(.loading)
    do {
      try await history.flush()
      guard phase != .finished else { return }
      _ = try await historyMutation.run(
        mutation,
        accept: { [self] snapshot in
          restore(snapshot)
          if phase == .finished {
            selectedRecords.stop()
            history.memories.invalidate()
          }
        })
      guard phase != .finished else { return }
      try await history.refreshMemories()
    } catch { if phase != .finished { history.recordFailure(error) } }
    guard phase != .finished else { return }
    setPhase(.ready)
  }

  package func resume() {
    guard phase == .finished else { return }
    conversationLifetime = SpeechModelLifetime()
    history.resumeSaving()
    selectedRecords.refresh()
    setPhase(history.isLoaded ? .ready : .loading)
  }

  package func updateProfile(_ profile: CharacterChatProfile, languageOverride: String? = nil) {
    pendingProfile = .init(profile: profile, languageOverride: languageOverride)
    applyPendingProfile()
  }

  private func applyPendingProfile() {
    guard canCompose, !isVoiceConversationActive, let update = pendingProfile else { return }
    pendingProfile = nil
    if languageOverride != update.languageOverride
      || profile.languageIdentifier != update.profile.languageIdentifier
    {
      language = update.languageOverride ?? update.profile.languageIdentifier
    }
    languageOverride = update.languageOverride
    profile = update.profile
  }

  package func showChat() {
    voiceActivation = UUID()
    mode = .chat
    diagnostics.modeChanged(.chat)
    spokenReplies = false
    if isVoiceConversationActive { stopVoiceConversation() }
    onChange?()
  }

  package func startTalk() async {
    guard canCompose || phase == .loading else { return }
    let activation = UUID()
    voiceActivation = activation
    mode = .talk
    diagnostics.modeChanged(.talk)
    spokenReplies = true
    onChange?()
    await restoreHistory()
    guard voiceActivation == activation, canCompose else { return }
    await refreshAvailability()
    onChange?()
    guard voiceActivation == activation, mode == .talk, case .available = readiness, canCompose
    else { return }
    voiceDraft = draft
    draft = ""
    startListening()
  }

  private func saveCheckpoint() {
    guard !isRestoringHistory else { return }
    history.update(
      .init(
        memory: memory, draft: voiceDraft ?? draft, language: language,
        readingMessageID: history.checkpoint.readingMessageID,
        selectedRecords: selectedRecords.selection))
  }

  private var pendingVoiceText: String {
    pendingVoiceTurns.sorted { $0.key < $1.key }.map(\.value).filter { !$0.isEmpty }
      .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func cancelReply(because reason: DiagnosticEvent.Reason) {
    if operation != nil || isWorking {
      diagnostics.delivery(spokenDelivery?.snapshot, turn: turnID)
      diagnostics.record(.cancelled, turn: turnID, reason: reason)
    }
    voiceInterruption.cancel()
    let previous = turnID
    let previousSpeech = speechID
    spokenDelivery?.endSpeech(previousSpeech)
    markInterrupted(previous)
    saveSpokenProgress(for: replayMessageID ?? previous)
    turnID = UUID()
    speechID = UUID()
    operation?.cancel()
    operation = nil
    speechDrain = Task { [speech = services.speech, speechDrain] in
      await speechDrain?.value
      await speech.stop(id: previousSpeech)
    }
  }

  private func setPhase(_ value: Phase) {
    diagnostics.phaseChanged(value, turn: turnID)
    phase = value
    if value == .ready { applyPendingProfile() }
    audioLevel = 0
    onChange?()
  }
}
