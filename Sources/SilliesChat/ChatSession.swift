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
  package let profile: CharacterChatProfile
  package private(set) var messages: [ChatMessage] = []
  package private(set) var phase = Phase.ready
  package private(set) var failure: SessionFailure?
  package private(set) var notice: ChatNotice?
  package private(set) var audioLevel = 0.0
  package var draft = ""
  package var language: String
  package var spokenReplies = true
  package var onChange: (@MainActor () -> Void)?
  package var onFinish: (@MainActor () -> Void)?
  @ObservationIgnored private let services: ChatServices
  @ObservationIgnored private let microphone: ChatMicrophone
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var turnID = UUID()

  package init(companionName: String, profile: CharacterChatProfile, services: ChatServices) {
    self.companionName = companionName
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
    case .ready: "Ready to chat"
    case .preparingMicrophone: "Getting the microphone ready…"
    case .listening: "Listening…"
    case .finalizing: "Finishing your words…"
    case .thinking: "Thinking…"
    case .preparingVoice: "Getting the voice ready…"
    case .speaking: "Speaking…"
    case .finished: "Chat finished"
    }
  }

  package func send() {
    guard canSend else { return }
    messages.append(.init(role: .user, text: draft.trimmingCharacters(in: .whitespacesAndNewlines)))
    draft = ""
    requestReply()
  }

  package func retry() { if canRetry { requestReply() } }

  package func startListening() {
    guard canCompose, draft.isEmpty else { return }
    failure = nil
    setPhase(.preparingMicrophone)
    microphone.start(language: language) { [weak self] in self?.receiveCapture($0) }
  }

  package func finishListening() {
    guard isRecording else { return }
    setPhase(.finalizing)
    microphone.finish { [weak self] result in
      guard let self, self.phase == .finalizing else { return }
      self.preserveFinalWords(result)
      self.setPhase(.ready)
      // Recognition is finalized first; the user can review or correct their words before sending.
    }
  }

  package func interrupt() {
    guard isWorking else { return }
    cancelReply()
    setPhase(.ready)
  }

  package func finish(completion: @escaping @MainActor () -> Void) {
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
        self.setPhase(.ready)
      } catch {
        guard let self, self.turnID == token, !Task.isCancelled else { return }
        self.failure = SessionFailure(error, category: .unknown)
        self.operation = nil
        self.setPhase(.ready)
      }
    }
  }

  private func receiveCapture(_ update: AudioCaptureUpdate) {
    guard isRecording else { return }
    switch update {
    case .capturing: setPhase(.listening)
    case .transcript(let text, let level, _):
      draft = text
      audioLevel = level
      onChange?()
      if text.count >= ChatContext.maximumMessageCharacters {
        notice = .reviewMessage("This message is getting long. Review your words before sending.")
        finishListening()
      }
    case .failed(let error), .transcriptionStopped(let error):
      failure = error
      setPhase(.finalizing)
      microphone.finish { [weak self] result in
        guard let self, self.phase == .finalizing else { return }
        self.preserveFinalWords(result)
        self.setPhase(.ready)
      }
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
    guard let result else { return }
    let text = result.plainText.isEmpty ? result.transcript : result.plainText
    if !text.isEmpty { draft = text }
    if let failure = result.failure { self.failure = failure }
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
