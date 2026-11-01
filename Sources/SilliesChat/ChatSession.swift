import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesTTS

/// Owns conversation turns; capture, reasoning, synthesis and hardware playback are injected ports.
@MainActor @Observable
package final class ChatSession {
  package enum Phase: Sendable {
    case ready, preparingMicrophone, listening, finalizing, thinking, preparingVoice, speaking,
      finished
  }
  package let companionName: String
  package let companionID: String
  package let profile: CharacterChatProfile
  package private(set) var messages: [ChatMessage] = []
  package private(set) var streamedText = ""
  @ObservationIgnored private var streamingMessageID: UUID?
  package private(set) var phase = Phase.ready
  package private(set) var failure: SessionFailure?
  package private(set) var notice: ChatNotice?
  package private(set) var audioLevel = 0.0
  package var draft = ""
  package var language: String
  package var spokenReplies = true
  package private(set) var isVoiceConversationActive = false
  package private(set) var discoveredSources: [ChatSource] = []
  private var sourceCardOwners: [UUID: UUID] = [:]
  @ObservationIgnored private var memory = ConversationMemory()
  private var toolActivity: String?
  package var onChange: (@MainActor () -> Void)?
  package var onFinish: (@MainActor () -> Void)?
  @ObservationIgnored private let services: ChatServices
  @ObservationIgnored private let microphone: ChatMicrophone
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var turnID = UUID()
  @ObservationIgnored private var pendingVoiceTurns: [Int: String] = [:]
  @ObservationIgnored private var voiceFinalizations = 0
  @ObservationIgnored private var voiceSequence = 0
  @ObservationIgnored private var spokenDelivery: ChatTurnDelivery?
  @ObservationIgnored private var voiceTurnEndedAt: ContinuousClock.Instant?
  @ObservationIgnored private let conversationLifetime = SpeechModelLifetime()
  package var firstTextLatency: Duration? { spokenDelivery?.snapshot.firstText }
  package var firstAudioLatency: Duration? { spokenDelivery?.snapshot.firstAudio }
  package var firstPCMLatency: Duration? { spokenDelivery?.snapshot.firstPCM }
  package var voicePreparedLatency: Duration? { spokenDelivery?.snapshot.voicePrepared }

  package init(
    companionName: String, profile: CharacterChatProfile, services: ChatServices,
    companionID: String = ""
  ) {
    self.companionName = companionName
    self.companionID = companionID
    self.profile = profile
    language = profile.languageIdentifier
    self.services = services
    microphone = ChatMicrophone(services: services)
  }

  deinit { Task { [conversationLifetime] in await conversationLifetime.end() } }

  package var isRecording: Bool { phase == .preparingMicrophone || phase == .listening }
  package var isWorking: Bool { [.thinking, .preparingVoice, .speaking].contains(phase) }
  package var canCompose: Bool { phase == .ready }
  package var canSend: Bool {
    canCompose && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.count <= ChatContext.maximumMessageCharacters
  }
  package var canRetry: Bool {
    canCompose && (messages.last?.role == .user || messages.last?.completion == .interrupted)
  }
  package var recoverySettingsDestination: ChatNotice.SettingsDestination? {
    switch failure?.category {
    case .textGeneration: .textModels
    case .speechSynthesis: .voices
    default: notice?.settingsDestination
    }
  }
  package var transcript: String {
    ChatTranscript.render(messages.map { presentedMessage($0) }, companionName: companionName)
  }
  package var status: String {
    switch phase {
    case .ready: String(localized: "Ready to chat")
    case .preparingMicrophone: String(localized: "Getting the microphone ready…")
    case .listening: String(localized: "Listening…")
    case .finalizing: String(localized: "Finishing your words…")
    case .thinking: toolActivity ?? String(localized: "Thinking…")
    case .preparingVoice: String(localized: "Getting the voice ready…")
    case .speaking: String(localized: "Speaking…")
    case .finished: String(localized: "Chat finished")
    }
  }

  package func send() {
    guard canSend else { return }
    messages.append(.init(role: .user, text: draft.trimmingCharacters(in: .whitespacesAndNewlines)))
    draft = ""
    requestReply()
  }

  package func retry() {
    guard canRetry else { return }
    if messages.last?.completion == .interrupted { messages.removeLast() }
    rebuildSourceCardOwners()
    requestReply()
  }

  package func refreshAvailability() async {
    guard phase == .ready else { return }
    let requestedLanguage = language
    let requestedSpokenReplies = spokenReplies
    let requestedTurn = turnID
    let textNotice = await services.conversation.availabilityNotice(
      localeIdentifier: requestedLanguage)
    let voiceNotice =
      requestedSpokenReplies
      ? await services.speech.availabilityNotice(language: requestedLanguage) : nil
    guard !Task.isCancelled, phase == .ready, language == requestedLanguage,
      spokenReplies == requestedSpokenReplies, turnID == requestedTurn
    else { return }
    notice =
      textNotice.map(ChatNotice.textUnavailable) ?? voiceNotice.map(ChatNotice.voiceUnavailable)
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

  package func stopVoiceConversation() {
    guard isVoiceConversationActive else { return }
    isVoiceConversationActive = false
    voiceTurnEndedAt = nil
    cancelReply()
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
        self.failure = failure
        if isVoiceConversationActive { stopVoiceConversation() }
        return
      }
    }
    guard isVoiceConversationActive, phase == .finalizing, voiceFinalizations == 0 else { return }
    draft = pendingVoiceText
    pendingVoiceTurns.removeAll()
    voiceSequence = 0
    setPhase(.ready)
    if canSend {
      send()
    } else if draft.isEmpty {
      voiceTurnEndedAt = nil
      setPhase(.listening)
    } else {
      stopVoiceConversation()
    }
  }

  package func interrupt() {
    guard isWorking else { return }
    cancelReply()
    setPhase(isVoiceConversationActive ? .listening : .ready)
  }

  package func finish(completion: @escaping @MainActor () -> Void) {
    Task { [conversationLifetime] in await conversationLifetime.end() }
    isVoiceConversationActive = false
    voiceTurnEndedAt = nil
    cancelReply()
    setPhase(.finished)
    microphone.finish { [self] result in
      preserveFinalWords(result)
      completion()
    }
  }

  private func requestReply() {
    guard phase == .ready else { return }
    failure = nil
    notice = nil
    toolActivity = nil
    discoveredSources = []
    let token = UUID()
    turnID = token
    let delivery = ChatTurnDelivery(started: voiceTurnEndedAt ?? .now)
    spokenDelivery = delivery
    voiceTurnEndedAt = nil
    let profile = CharacterChatProfile(
      personality: profile.personality, languageIdentifier: language,
      preferredVoices: profile.preferredVoices)
    let context = ChatContext(
      companionName: companionName, profile: profile, messages: messages, memory: memory
    ).inTurn(token, session: conversationLifetime.id)
    setPhase(.thinking)
    operation = Task { [weak self, services, conversationLifetime] in
      do {
        await services.conversation.retain(for: conversationLifetime)
        let turn = ChatTurnOperation(
          services: services,
          delivery: .init(
            progress: { [weak self] progress in
              services.deliver { [weak self] in self?.receive(progress, turn: token) }
            },
            text: { [weak self] text in
              await delivery.receivedText()
              await self?.receiveText(text, turn: token)
            },
            textFinished: { [weak self] in
              await self?.waitingForVoice(turn: token)
            },
            playback: { [weak self] update in
              services.deliver { [weak self] in
                delivery.received(update)
                self?.receivePlayback(update, token: token)
              }
            }), voiceLifetime: conversationLifetime)
        let result = try await turn.run(
          context, output: self?.spokenReplies == true ? .spoken : .text)
        try Task.checkCancellation()
        guard let self, self.turnID == token else { return }
        self.completeReply(result.reply, turn: token)
        switch result.voice {
        case .finished: break
        case .notice(let message): self.notice = .voiceUnavailable(message)
        case .failed(let failure): self.failure = failure
        }
        self.operation = nil
        self.setPhase(self.isVoiceConversationActive ? .listening : .ready)
      } catch {
        guard let self, self.turnID == token, !Task.isCancelled else { return }
        self.markInterrupted(token)
        // Recognition can preempt inference before its speech-start update reaches the UI.
        if error is CancellationError {
          self.operation = nil
          self.setPhase(self.isVoiceConversationActive ? .listening : .ready)
          return
        }
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
    streamedText = text
    beginReplyPresentation(turn)
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
    .withDelivery(.complete, spokenText: spokenDelivery?.snapshot.spokenText)
    if let index = messages.firstIndex(where: { $0.id == turn }) {
      messages[index] = message
    } else {
      messages.append(message)
    }
    clearStreamPresentation()
    rebuildSourceCardOwners()
    discoveredSources = []
    toolActivity = nil
  }

  private func markInterrupted(_ turn: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == turn }),
      messages[index].completion == .streaming
    else { return }
    messages[index] = presentedMessage(messages[index]).withDelivery(
      .interrupted, spokenText: spokenDelivery?.snapshot.spokenText)
    clearStreamPresentation()
  }

  private func clearStreamPresentation() {
    streamingMessageID = nil
    streamedText = ""
  }

  private func receive(_ progress: ChatProgress, turn: UUID) {
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
    case .compacting: toolActivity = String(localized: "Remembering our conversation…")
    case .memory(let value):
      memory = value
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
    onChange?()
  }

  private func receiveCapture(_ update: AudioCaptureUpdate) {
    guard isVoiceConversationActive else { return }
    switch update {
    case .capturing: setPhase(.listening)
    case .speechStarted:
      cancelReply()
      draft = ""
      setPhase(.listening)
    case .speechEnded: finishListening()
    case .transcript(let text, let level, _):
      guard phase == .listening else { return }
      draft = text
      audioLevel = level
      onChange?()
      if text.count >= ChatContext.maximumMessageCharacters {
        finishListening()
      }
    case .failed(let error), .transcriptionStopped(let error):
      failure = error
      stopVoiceConversation()
    default: break
    }
  }

  private func receivePlayback(_ update: SpeechPlaybackUpdate, token: UUID) {
    guard turnID == token, phase != .finished else { return }
    switch update {
    case .milestone: return
    case .speaking(let level):
      guard isWorking else { return }
      phase = .speaking
      audioLevel = level
    case .finished, .interrupted: audioLevel = 0
    case .utteranceFinished:
      guard streamingMessageID != token, let index = messages.firstIndex(where: { $0.id == token })
      else { return }
      let message = messages[index]
      messages[index] = message.withDelivery(
        message.completion ?? .complete, spokenText: spokenDelivery?.snapshot.spokenText)
    }
    onChange?()
  }

  private func preserveFinalWords(_ result: AudioCaptureResult?) {
    let unfinished = result.map { $0.plainText.isEmpty ? $0.transcript : $0.plainText } ?? ""
    let text = [pendingVoiceText, unfinished].filter { !$0.isEmpty }.joined(separator: " ")
    if !text.isEmpty { draft = text }
    if let failure = result?.failure { self.failure = failure }
    pendingVoiceTurns.removeAll()
    voiceFinalizations = 0
    voiceSequence = 0
  }

  private var pendingVoiceText: String {
    pendingVoiceTurns.sorted { $0.key < $1.key }.map(\.value).filter { !$0.isEmpty }
      .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func cancelReply() {
    let previous = turnID
    markInterrupted(previous)
    turnID = UUID()
    operation?.cancel()
    operation = nil
    Task { [speech = services.speech] in await speech.stop(id: previous) }
  }

  private func setPhase(_ value: Phase) {
    phase = value
    audioLevel = 0
    onChange?()
  }
}
