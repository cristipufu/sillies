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
  private static let maximumMessages = 100
  package let companionName: String
  package let companionID: String
  package let profile: CharacterChatProfile
  package private(set) var messages: [ChatMessage] = []
  package private(set) var phase = Phase.ready
  package private(set) var failure: SessionFailure?
  package private(set) var notice: ChatNotice?
  package private(set) var audioLevel = 0.0
  package var draft = ""
  package var language: String
  package var spokenReplies = true
  package private(set) var isVoiceConversationActive = false
  package var onChange: (@MainActor () -> Void)?
  package var onFinish: (@MainActor () -> Void)?
  @ObservationIgnored private let services: ChatServices
  @ObservationIgnored private let microphone: ChatMicrophone
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var turnID = UUID()
  @ObservationIgnored private var pendingVoiceTurns: [Int: String] = [:]
  @ObservationIgnored private var voiceFinalizations = 0
  @ObservationIgnored private var voiceSequence = 0

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

  package var isRecording: Bool { phase == .preparingMicrophone || phase == .listening }
  package var isWorking: Bool { [.thinking, .preparingVoice, .speaking].contains(phase) }
  package var canCompose: Bool { phase == .ready }
  package var canSend: Bool {
    canCompose && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.count <= ChatContext.maximumMessageCharacters
      && messages.count < Self.maximumMessages
  }
  package var canRetry: Bool { canCompose && messages.last?.role == .user }
  package var hasReachedMessageLimit: Bool { messages.count >= Self.maximumMessages }
  package var transcript: String {
    messages.map { "\($0.role == .user ? "You" : companionName)\n\($0.text)" }.joined(
      separator: "\n\n")
  }
  package var status: String {
    switch phase {
    case .ready: String(localized: "Ready to chat")
    case .preparingMicrophone: String(localized: "Getting the microphone ready…")
    case .listening: String(localized: "Listening…")
    case .finalizing: String(localized: "Finishing your words…")
    case .thinking: String(localized: "Thinking…")
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

  package func retry() { if canRetry { requestReply() } }

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
    isVoiceConversationActive = false
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
    let token = UUID()
    turnID = token
    let profile = CharacterChatProfile(
      personality: profile.personality, languageIdentifier: language,
      preferredVoices: profile.preferredVoices)
    let context = ChatContext(companionName: companionName, profile: profile, messages: messages)
    setPhase(.thinking)
    operation = Task { [weak self, services] in
      do {
        let reply = try await services.conversation.reply(to: context)
        try Task.checkCancellation()
        guard let self, self.turnID == token else { return }
        self.messages.append(
          .init(role: .companion, text: String(reply.prefix(ChatContext.maximumMessageCharacters))))
        if self.spokenReplies {
          self.setPhase(.preparingVoice)
          let notice = try await services.speech.speak(
            .init(id: token, text: reply, profile: profile)
          ) { [weak self] update in
            services.deliver { [weak self] in self?.receivePlayback(update, token: token) }
          }
          try Task.checkCancellation()
          guard self.turnID == token else { return }
          self.notice = notice.map(ChatNotice.voiceUnavailable)
        }
        try Task.checkCancellation()
        guard self.turnID == token else { return }
        self.operation = nil
        self.setPhase(self.isVoiceConversationActive ? .listening : .ready)
      } catch {
        guard let self, self.turnID == token, !Task.isCancelled else { return }
        // Recognition can preempt inference before its speech-start update reaches the UI.
        if error is CancellationError {
          self.operation = nil
          self.setPhase(self.isVoiceConversationActive ? .listening : .ready)
          return
        }
        self.failure = SessionFailure(error, category: .unknown)
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
    guard turnID == token, phase == .preparingVoice || phase == .speaking else { return }
    switch update {
    case .speaking(let level):
      phase = .speaking
      audioLevel = level
    case .finished: audioLevel = 0
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
