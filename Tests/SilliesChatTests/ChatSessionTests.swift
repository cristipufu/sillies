import Foundation
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesTTS
import Synchronization
import Testing

private actor ReplyProbe: ConversationResponding {
  var contexts: [ChatContext] = []
  var delayed: CheckedContinuation<String, Never>?
  let mode: Mode
  enum Mode { case immediate, delayed }
  init(_ mode: Mode = .immediate) { self.mode = mode }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    contexts.append(context)
    if mode == .delayed { return await .init(text: withCheckedContinuation { delayed = $0 }) }
    return .init(text: "Mâine, Ștefan trimite API_v2 la 14:30.")
  }
  func resolve() {
    delayed?.resume(returning: "Late reply")
    delayed = nil
  }
}

private actor VoiceProbe: ChatSpeechOutput {
  var requests: [ChatSpeechRequest] = []
  let fails: Bool
  let unavailableMessage: String?
  init(fails: Bool = false, unavailableMessage: String? = nil) {
    self.fails = fails
    self.unavailableMessage = unavailableMessage
  }
  func availabilityNotice(language: String) async -> String? { unavailableMessage }
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    requests.append(request)
    if fails { throw TTSError.invalidAudio }
    receive(.speaking(level: 0.5))
    receive(.finished)
    return nil
  }
  func stop(id: UUID) {}
}

private final class CaptureProbe: ConversationCapture, Sendable {
  let words = Mutex("Salut, Ștefan!")
  let started = Mutex(0)
  let stopped = Mutex(0)
  let update: @Sendable (AudioCaptureUpdate) -> Void
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() {
    started.withLock { $0 += 1 }
    update(.capturing("Listening"))
  }
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    completion(takeResult())
  }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    stopped.withLock { $0 += 1 }
    completion(takeResult())
  }
  private func takeResult() -> AudioCaptureResult {
    let text = words.withLock { value in
      let result = value
      value = ""
      return result
    }
    return AudioCaptureResult(transcript: text, recordingURL: nil, duration: 1, failure: nil)
  }

}

private final class FinalizingCaptureProbe: ConversationCapture, Sendable {
  let completion = Mutex<(@Sendable (AudioCaptureResult) -> Void)?>(nil)
  let turnCompletion = Mutex<(@Sendable (AudioCaptureResult) -> Void)?>(nil)
  let update: @Sendable (AudioCaptureUpdate) -> Void
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() { update(.capturing("Listening")) }
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    turnCompletion.withLock { $0 = completion }
  }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    self.completion.withLock { $0 = completion }
  }
  func finalize() {
    let callback = completion.withLock { $0 }
    let result = AudioCaptureResult(
      transcript: "The final words survive.", recordingURL: nil, duration: 1, failure: nil)
    let turn = turnCompletion.withLock { $0 }
    let remainder =
      turn == nil
      ? result : AudioCaptureResult(transcript: "", recordingURL: nil, duration: 0, failure: nil)
    callback?(remainder)
    callback?(remainder)  // A duplicate device callback must not save twice.
    // Deliberately deliver the detached turn after device teardown.
    turn?(result)
    turn?(result)
  }
}

private enum FinishTiming: CaseIterable { case listening, finalizing }

@Test(arguments: FinishTiming.allCases) @MainActor
private func chatFinishPreservesFinalWordsBeforeSaving(_ timing: FinishTiming) async throws {
  let capture = Mutex<FinalizingCaptureProbe?>(nil)
  let chat = session(
    reply: ReplyProbe(), voice: VoiceProbe(),
    capture: { _, update in
      let probe = FinalizingCaptureProbe(update: update)
      capture.withLock { $0 = probe }
      return probe
    })
  chat.startListening()
  try await waitFor { chat.phase == .listening }
  if timing == .finalizing { chat.finishListening() }
  var saves: [String] = []
  chat.finish { saves.append(chat.draft) }
  #expect(saves.isEmpty)
  let probe = try #require(capture.withLock { $0 })
  probe.finalize()
  try await waitFor { !saves.isEmpty }
  #expect(saves == ["The final words survive."])
  #expect(chat.phase == .finished)
}

@MainActor private func session(
  reply: any ConversationResponding, voice: any ChatSpeechOutput,
  capture: (
    @Sendable (AudioCaptureConfiguration, @escaping @Sendable (AudioCaptureUpdate) -> Void) ->
      any ConversationCapture
  )? = nil
) -> ChatSession {
  ChatSession(
    companionName: "Mochi",
    profile: .init(personality: "Warm and playful", languageIdentifier: "ro"),
    services: .init(
      captureFactory: capture ?? { _, update in CaptureProbe(update: update) },
      loadLanguages: {
        .init(languages: [.init(id: "ro-RO", name: "Romanian", isInstalled: true)])
      },
      conversation: reply, speech: voice,
      deliver: { action in Task { @MainActor in action() } }))
}

@MainActor private func waitFor(_ predicate: @MainActor () async -> Bool) async throws {
  for _ in 0..<200 {
    if await predicate() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Chat did not reach the expected state within one second")
}

@Test @MainActor func chatVoiceSetupIsOptionalAndDoesNotStartPlayback() async {
  let voice = VoiceProbe(unavailableMessage: "Choose a downloaded voice for spoken replies.")
  let chat = session(reply: ReplyProbe(), voice: voice)
  await chat.refreshAvailability()
  #expect(chat.notice?.settingsDestination == .voices)
  #expect(chat.canCompose)
  #expect(await voice.requests.isEmpty)
  chat.spokenReplies = false
  await chat.refreshAvailability()
  #expect(chat.notice == nil)
  chat.finish {}
}

@Test @MainActor func chatPreservesRomanianAndReplyWhenVoiceFails() async throws {
  let reply = ReplyProbe()
  let voice = VoiceProbe(fails: true)
  let chat = session(reply: reply, voice: voice)
  chat.draft = "Ștefan, at 14:30, API_v2."
  chat.send()
  try await waitFor { chat.phase == .ready }
  #expect(chat.messages.count == 2)
  #expect(chat.messages.last?.text == "Mâine, Ștefan trimite API_v2 la 14:30.")
  #expect(chat.failure != nil)
  #expect(chat.failure?.category == .speechSynthesis)
  #expect(chat.recoverySettingsDestination == .voices)
  #expect(await reply.contexts.first?.profile.languageIdentifier == "ro")
  #expect(await voice.requests.first?.text == chat.messages.last?.text)
  chat.finish {}
}

private actor RecoveringReplyProbe: ConversationResponding {
  var contexts: [ChatContext] = []
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    contexts.append(context)
    if contexts.count == 1 {
      throw NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1)
    }
    return .init(text: "I'm Bolt, your window companion.")
  }
}

@Test @MainActor func firstSpokenTurnSurvivesGenerationFailureAndCanBeRetried() async throws {
  let reply = RecoveringReplyProbe()
  let voice = VoiceProbe()
  let capture = Mutex<CaptureProbe?>(nil)
  let chat = session(
    reply: reply, voice: voice,
    capture: { _, update in
      let probe = CaptureProbe(update: update)
      probe.words.withLock { $0 = "Hey man, what's uh what's your name?" }
      capture.withLock { $0 = probe }
      return probe
    })
  chat.startListening()
  try await waitFor { chat.phase == .listening }
  let microphone = try #require(capture.withLock { $0 })
  microphone.update(.speechEnded)
  try await waitFor { chat.phase == .ready && chat.failure != nil }
  #expect(chat.messages.count == 1)
  #expect(chat.messages.first?.text == "Hey man, what's uh what's your name?")
  #expect(chat.failure?.category == .textGeneration)
  #expect(chat.recoverySettingsDestination == .textModels)
  #expect(chat.canRetry)
  #expect(!chat.isVoiceConversationActive)
  #expect(microphone.stopped.withLock { $0 } == 1)
  #expect(await voice.requests.isEmpty)
  chat.retry()
  try await waitFor { chat.phase == .ready && chat.messages.count == 2 }
  #expect(chat.failure == nil)
  #expect(await reply.contexts.count == 2)
  #expect(await reply.contexts.allSatisfy { $0.messages.count == 1 })
  #expect(await voice.requests.count == 1)
  chat.finish {}
}

@Test @MainActor func chatRejectsLateReplyAfterFinish() async throws {
  let reply = ReplyProbe(.delayed)
  let voice = VoiceProbe()
  let chat = session(reply: reply, voice: voice)
  chat.draft = "Hello"
  chat.send()
  try await waitFor { await reply.delayed != nil }
  chat.finish {}
  await reply.resolve()
  try await Task.sleep(for: .milliseconds(20))
  #expect(chat.phase == .finished)
  #expect(chat.messages.count == 1)
  #expect(await voice.requests.isEmpty)
}

@Test @MainActor func chatVoiceConversationAutomaticallySendsFinalizedWordsAndKeepsListening()
  async throws
{
  let captures = Mutex<[CaptureProbe]>([])
  let chat = session(
    reply: ReplyProbe(), voice: VoiceProbe(),
    capture: { configuration, update in
      #expect(configuration.sources == [.microphone])
      #expect(configuration.recordingURL == nil)
      #expect(configuration.recognitionContext.priority == .interactive)
      let probe = CaptureProbe(update: update)
      captures.withLock { $0.append(probe) }
      return probe
    })
  #expect(captures.withLock { $0.isEmpty })
  chat.startListening()
  try await waitFor { chat.phase == .listening }
  let capture = try #require(captures.withLock { $0.first })
  capture.update(.speechStarted)
  capture.update(.speechEnded)
  try await waitFor { chat.messages.count == 2 && chat.phase == .listening }
  #expect(chat.messages.first?.text == "Salut, Ștefan!")
  #expect(chat.draft.isEmpty)
  #expect(capture.stopped.withLock { $0 } == 0)
  capture.words.withLock { $0 = "And another thought." }
  capture.update(.speechStarted)
  capture.update(.speechEnded)
  try await waitFor { chat.messages.count == 4 && chat.phase == .listening }
  #expect(chat.messages[2].text == "And another thought.")
  chat.stopVoiceConversation()
  try await waitFor { chat.phase == .ready }
  #expect(capture.stopped.withLock { $0 } == 1)
  #expect(!chat.isVoiceConversationActive)
  chat.finish {}
}

@Test func chatRetainsFullHistoryAndSpokenChunksStayBounded() {
  let messages = (0..<100).map { _ in
    ChatMessage(role: .user, text: String(repeating: "a", count: 1_000))
  }
  let context = ChatContext(
    companionName: "Mochi", profile: .init(personality: "Playful"), messages: messages)
  #expect(context.messages == messages)
  let text = String(repeating: "Mâine Ștefan folosește API_v2. ", count: 100)
  let chunks = SpokenTextChunks.split(text, maximumCharacters: 100)
  #expect(chunks.allSatisfy { $0.count <= 100 })
  #expect(chunks.joined(separator: " ") == text.trimmingCharacters(in: .whitespacesAndNewlines))
}

private actor ConversationalVoiceProbe: ChatSpeechOutput {
  var requests: [ChatSpeechRequest] = []
  var stopped: [UUID] = []
  private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    requests.append(request)
    receive(.speaking(level: 0.5))
    return await withCheckedContinuation { pending[request.id] = $0 }
  }
  func stop(id: UUID) {
    stopped.append(id)
    pending.removeValue(forKey: id)?.resume(returning: nil)
  }
}

@Test @MainActor func chatSpeechInterruptsPlaybackWithoutRestartingMicrophone() async throws {
  let captures = Mutex<[CaptureProbe]>([])
  let voice = ConversationalVoiceProbe()
  let chat = session(
    reply: ReplyProbe(), voice: voice,
    capture: { _, update in
      let capture = CaptureProbe(update: update)
      captures.withLock { $0.append(capture) }
      return capture
    })
  chat.startListening()
  try await waitFor { chat.phase == .listening }
  let capture = try #require(captures.withLock { $0.first })
  capture.update(.speechStarted)
  capture.update(.speechEnded)
  try await waitFor { chat.phase == .speaking }
  let first = try #require(await voice.requests.first?.id)
  capture.update(.speechStarted)
  try await waitFor { await voice.stopped.contains(first) && chat.phase == .listening }
  #expect(chat.isVoiceConversationActive)
  #expect(capture.stopped.withLock { $0 } == 0)
  capture.words.withLock { $0 = "Wait, I meant something else." }
  capture.update(.speechEnded)
  try await waitFor { await voice.requests.count == 2 && chat.phase == .speaking }
  #expect(captures.withLock { $0.count } == 1)
  #expect(chat.messages[2].text == "Wait, I meant something else.")
  chat.finish {}
}

private actor MemoryReplyProbe: ConversationResponding {
  var contexts: [ChatContext] = []
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    -> ChatReply
  {
    contexts.append(context)
    let memory = ConversationMemory(
      summary: "The user's name is Ada.", throughMessageID: context.messages.dropLast().last?.id)
    progress(.compacting)
    progress(.memory(memory))
    return .init(text: "Hello Ada.", memory: memory)
  }
}

@Test @MainActor func chatContinuesPastOneHundredMessagesAndCarriesMemoryBetweenTurns() async throws
{
  let reply = MemoryReplyProbe()
  let chat = session(reply: reply, voice: VoiceProbe())
  chat.spokenReplies = false
  for index in 0..<60 {
    chat.draft = "Question \(index)"
    #expect(chat.canSend)
    chat.send()
    try await waitFor { chat.phase == .ready }
  }
  #expect(chat.messages.count == 120)
  #expect(chat.transcript.contains("Question 0"))
  #expect(chat.transcript.contains("Question 59"))
  let context = try #require(await reply.contexts.last)
  #expect(context.memory.summary.contains("Ada"))
  #expect(context.messages.count == 119)
  chat.finish {}
}

private actor SourceFailureProbe: ConversationResponding {
  let source: ChatSource
  init(source: ChatSource) { self.source = source }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void) throws
    -> ChatReply
  {
    progress(.sources([source]))
    throw SessionFailure(category: .unknown, message: "Generation failed after search")
  }
}

@Test @MainActor func chatKeepsFoundVaultCardsWhenTheFinalAnswerFails() async throws {
  let source = ChatSource(
    header: .init(
      SessionRecord(
        kind: .stash,
        origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Safari")))
    ), excerpt: "Saved URL")
  let chat = session(reply: SourceFailureProbe(source: source), voice: VoiceProbe())
  chat.spokenReplies = false
  chat.draft = "Find my saved links"
  chat.send()
  try await waitFor { chat.failure != nil }
  #expect(chat.canRetry)
  #expect(chat.discoveredSources.map(\.id) == [source.id])
  chat.finish {}
}

private actor StreamingReplyProbe: ConversationResponding {
  enum Ending { case complete, fail, rewrite }
  let ending: Ending
  var waiting: CheckedContinuation<Void, Never>?
  var completed = false
  init(_ ending: Ending = .complete) { self.ending = ending }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    try await streamReply(to: context, progress: progress, receive: { _ in })
  }
  func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    try await receive("Hello there. ")
    await withCheckedContinuation { waiting = $0 }
    try Task.checkCancellation()
    if ending == .fail {
      throw SessionFailure(category: .textGeneration, message: "Worker exited mid-reply")
    }
    try await receive("The rest arrives later.")
    completed = true
    return .init(
      text: ending == .rewrite
        ? "A different final answer." : "Hello there. The rest arrives later.")
  }
  func resume() {
    waiting?.resume()
    waiting = nil
  }
}

@Test @MainActor func chatShowsAndSpeaksTheFirstPhraseBeforeTextGenerationFinishes() async throws {
  let reply = StreamingReplyProbe()
  let voice = VoiceProbe()
  let chat = session(reply: reply, voice: voice)
  chat.draft = "Hello"
  chat.send()
  try await waitFor { await voice.requests.count == 1 }
  #expect(await !reply.completed)
  #expect(chat.messages.count == 2)
  #expect(chat.presentedMessage(try #require(chat.messages.last)).text == "Hello there. ")
  #expect(chat.messages.last?.completion == .streaming)
  #expect(chat.transcript.contains("Hello there."))
  #expect(chat.firstTextLatency != nil)
  #expect(chat.firstAudioLatency != nil)
  await reply.resume()
  try await waitFor { chat.phase == .ready }
  #expect(chat.messages.last?.text == "Hello there. The rest arrives later.")
  #expect(chat.messages.last?.completion == .complete)
  #expect(await voice.requests.map(\.text) == ["Hello there.", "The rest arrives later."])
  #expect(chat.messages.last?.spokenText == "Hello there. The rest arrives later.")
  chat.finish {}
}

@Test @MainActor func streamedVoiceFailureDoesNotDiscardOrStopTheTextBranch() async throws {
  let reply = StreamingReplyProbe()
  let voice = VoiceProbe(fails: true)
  let chat = session(reply: reply, voice: voice)
  chat.draft = "Hello"
  chat.send()
  try await waitFor { await voice.requests.count == 1 }
  await reply.resume()
  try await waitFor { chat.phase == .ready }
  #expect(chat.messages.last?.text == "Hello there. The rest arrives later.")
  #expect(chat.failure?.category == .speechSynthesis)
  #expect(await voice.requests.count == 1)
  #expect(chat.messages.last?.spokenText == "")
  chat.finish {}
}

@Test @MainActor func interruptingAStreamPreservesItsPartialReplyAndRejectsLateText() async throws {
  let reply = StreamingReplyProbe()
  let voice = VoiceProbe()
  let chat = session(reply: reply, voice: voice)
  chat.draft = "Hello"
  chat.send()
  try await waitFor { await voice.requests.count == 1 }
  chat.interrupt()
  #expect(chat.phase == .ready)
  #expect(chat.messages.last?.completion == .interrupted)
  #expect(chat.messages.last?.text == "Hello there. ")
  #expect(chat.canRetry)
  await reply.resume()
  try await Task.sleep(for: .milliseconds(20))
  #expect(chat.messages.count == 2)
  #expect(chat.messages.last?.text == "Hello there. ")
  #expect(await voice.requests.count == 1)
  chat.finish {}
}

@Test @MainActor func modelFailureAfterPartialOutputIsRecoverableWithoutAutomaticReplay()
  async throws
{
  for ending in [StreamingReplyProbe.Ending.fail, .rewrite] {
    let reply = StreamingReplyProbe(ending)
    let voice = VoiceProbe()
    let chat = session(reply: reply, voice: voice)
    chat.spokenReplies = false
    chat.draft = "Hello"
    chat.send()
    try await waitFor { await reply.waiting != nil }
    await reply.resume()
    try await waitFor { chat.failure != nil }
    #expect(chat.messages.count == 2)
    #expect(chat.messages.last?.completion == .interrupted)
    #expect(chat.messages.last?.text.hasPrefix("Hello there.") == true)
    #expect(chat.failure?.category == .textGeneration)
    #expect(chat.canRetry)
    #expect(await voice.requests.isEmpty)
    chat.finish {}
  }
}
