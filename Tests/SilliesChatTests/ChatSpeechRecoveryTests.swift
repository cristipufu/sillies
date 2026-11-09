import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import SilliesReasoning
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesChat

private enum PreemptionOrder: CaseIterable {
  case beforeSpeech, duringRecognition, afterEmptyResult
}

@Test @MainActor
private func chatAcousticEvidenceKeepsTheInterruptedTurnAcrossRecognitionCancellation() {
  let events = Mutex<[DiagnosticEvent]>([])
  let diagnostics = ChatDiagnostics(sink: .init { event in events.withLock { $0.append(event) } })
  let original = UUID()
  let replacement = UUID()
  let utterance = UUID()
  diagnostics.phaseChanged(.speaking, turn: original)
  diagnostics.acoustics(
    .init(boundary: .onset, window: .init(), delivery: .init(), echo: .init()),
    utterance: utterance, turn: original)
  diagnostics.record(.cancelled, turn: original, reason: .recognizedWords)
  diagnostics.phaseChanged(.listening, turn: replacement)
  diagnostics.acoustics(
    .init(boundary: .endpoint, window: .init(), delivery: .init(), echo: .init()),
    utterance: utterance, turn: replacement)
  let evidence = events.withLock { $0.filter { $0.action == .acousticAssessment } }
  #expect(evidence.map(\.operation) == [original, original])
  #expect(evidence.map { $0.acoustics?.utterance } == [utterance, utterance])
  #expect(evidence.map { $0.acoustics?.boundary } == [.onset, .endpoint])
  #expect(evidence[0].relatedOperation == evidence[1].relatedOperation)
}

@Test(arguments: PreemptionOrder.allCases) @MainActor
private func emptyInterruptionRecoversOnlyUnconfirmedPhrasesWithoutRepeatingInference(
  _ order: PreemptionOrder
) async throws {
  let harness = RecoveryHarness()
  let chat = harness.chat
  chat.startListening()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Find my tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let voiceWaiting = await harness.voice.isWaiting
    return await harness.reasoning.isWaiting && voiceWaiting
  }
  if order == .beforeSpeech {
    await harness.reasoning.preempt()
    try await recoveryWait { chat.phase == .listening && chat.isWorking }
  }
  capture.update(.speechStarted)
  try await recoveryWait { chat.phase == .listening }
  if order == .duringRecognition { await harness.reasoning.preempt() }
  capture.update(.speechEnded(nil))
  if order == .afterEmptyResult {
    try await recoveryWait { await harness.voice.resumed == 1 }
    await harness.reasoning.preempt()
  }
  try await recoveryWait { await harness.voice.attempts.count == 2 && !chat.isWorking }
  let attempts = await harness.voice.attempts
  #expect(attempts[0].id != attempts[1].id)
  #expect(attempts[1].phrases == Array(RecoveryReasoning.phrases.dropFirst()))
  #expect(await harness.reasoning.requests == 1)
  #expect(chat.messages.filter { $0.role == .user }.count == 1)
  #expect(chat.messages.filter { $0.role == .companion }.count == 1)
  #expect(chat.messages.last?.spokenText == RecoveryReasoning.phrases.joined(separator: " "))
  #expect(chat.messages.last?.completion == .interrupted)
  #expect(chat.phase == .listening)
  #expect(chat.failure == nil)
  chat.finish {}
}

@Test @MainActor private func realWordsCancelRetainedSpeechBeforeTheNextReply() async throws {
  let harness = RecoveryHarness()
  let chat = harness.chat
  chat.startListening()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let voiceWaiting = await harness.voice.isWaiting
    return await harness.reasoning.isWaiting && voiceWaiting
  }
  await harness.reasoning.preempt()
  try await recoveryWait { chat.phase == .listening && chat.isWorking }
  capture.update(.speechStarted)
  capture.update(.transcript("Actually", level: 0.5, elapsed: 0.1))
  try await recoveryWait { !chat.isWorking && chat.draft == "Actually" }
  capture.finalText.withLock { $0 = "Actually, never mind" }
  capture.update(.speechEnded(nil))
  try await recoveryWait { await harness.reasoning.requests == 2 && !chat.isWorking }
  #expect(await harness.voice.attempts.count == 2)
  #expect(await harness.voice.attempts.last?.phrases == ["Of course."])
  #expect(
    chat.messages.filter { $0.role == .user }.map(\.text)
      == ["Tea instructions", "Actually, never mind"])
  chat.finish {}
}

@Test private func playbackProgressIgnoresDelayedCallbacksFromAnOldAttempt() {
  let delivery = ChatTurnDelivery(started: .now)
  let original = UUID()
  let resumed = UUID()
  for phrase in RecoveryReasoning.phrases { delivery.plannedSpeech(phrase) }
  delivery.beginSpeech(original)
  delivery.received(.utteranceFinished(RecoveryReasoning.phrases[0]), from: original)
  delivery.endSpeech(original)
  delivery.beginSpeech(resumed)
  #expect(!delivery.received(.utteranceFinished(RecoveryReasoning.phrases[1]), from: original))
  #expect(delivery.snapshot.speech.remainingPhrases.count == 2)
  delivery.received(.utteranceFinished(RecoveryReasoning.phrases[1]), from: resumed)
  #expect(delivery.snapshot.speech.remainingPhrases == [RecoveryReasoning.phrases[2]])
}

@Test @MainActor private func audioOnlyPreemptionRecoversACompletedAnswer() async throws {
  let harness = RecoveryHarness(ending: .complete)
  let chat = harness.chat
  chat.startListening()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let waiting = await harness.reasoning.isWaiting
    return await harness.voice.isWaiting && waiting
  }
  await harness.reasoning.preempt()
  capture.update(.speechStarted)
  try await recoveryWait { chat.phase == .listening }
  let original = try #require(await harness.voice.attempts.first?.id)
  await harness.voice.stop(id: original)
  capture.update(.speechEnded(nil))
  try await recoveryWait { await harness.voice.attempts.count == 2 && !chat.isWorking }
  #expect(chat.messages.last?.completion == .complete)
  #expect(chat.messages.last?.spokenText == RecoveryReasoning.phrases.joined(separator: " "))
  #expect(await harness.reasoning.requests == 1)
  chat.finish {}
}

@Test @MainActor private func closingDuringRecoveredSpeechDrainsTheReplay() async throws {
  let harness = RecoveryHarness(replay: .suspended)
  let chat = harness.chat
  chat.startListening()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let waiting = await harness.reasoning.isWaiting
    return await harness.voice.isWaiting && waiting
  }
  await harness.reasoning.preempt()
  try await recoveryWait { chat.phase == .listening && chat.isWorking }
  capture.update(.speechStarted)
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let waiting = await harness.voice.isWaiting
    return await harness.voice.attempts.count == 2 && waiting
  }
  await withCheckedContinuation { continuation in chat.finish { continuation.resume() } }
  try await recoveryWait { await !harness.voice.isWaiting }
  #expect(chat.phase == .finished)
  #expect(await harness.reasoning.requests == 1)
  #expect(chat.messages.last?.spokenText == RecoveryReasoning.phrases[0])
}

@MainActor private final class RecoveryHarness {
  let reasoning: RecoveryReasoning
  let voice: RecoveryVoice
  let capture: @Sendable () -> RecoveryCapture?
  let chat: ChatSession
  init(
    ending: RecoveryReasoning.Ending = .preempted, replay: RecoveryVoice.Replay = .immediate,
    diagnostics: DiagnosticSink = .disabled
  ) {
    reasoning = RecoveryReasoning(ending: ending)
    voice = RecoveryVoice(replay: replay)
    let captured = Mutex<RecoveryCapture?>(nil)
    capture = { captured.withLock { $0 } }
    chat = ChatSession(
      companionName: "Pogo", profile: .init(personality: "Playful", languageIdentifier: "en"),
      services: .init(
        captureFactory: { _, update in
          let input = RecoveryCapture(update: update)
          captured.withLock { $0 = input }
          return input
        },
        loadLanguages: {
          .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)])
        },
        conversation: reasoning, speech: voice,
        deliver: { action in Task { @MainActor in action() } }, history: .transient,
        diagnostics: diagnostics))
  }
}

@Test @MainActor private func chatCannotContinueSpeakingOverAnActiveUserUtterance() async throws {
  let detectedSpeech = Mutex(false)
  let harness = RecoveryHarness(
    ending: .complete,
    diagnostics: DiagnosticSink { event in
      if event.action == .speechDetected { detectedSpeech.withLock { $0 = true } }
    })
  let chat = harness.chat
  await chat.startTalk()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let waiting = await harness.reasoning.isWaiting
    return await harness.voice.isWaiting && waiting
  }
  chat.interrupt()
  await harness.reasoning.preempt()
  try await recoveryWait { chat.canContinueSpeaking }

  capture.update(.speechStarted)
  try await recoveryWait { detectedSpeech.withLock { $0 } }
  #expect(!chat.canContinueSpeaking)
  capture.update(.transcript("Another question", level: 0.5, elapsed: 0.2))
  try await recoveryWait { chat.draft == "Another question" }
  #expect(!chat.canContinueSpeaking)
  chat.continueSpeaking()
  #expect(chat.phase == .listening)
  guard chat.phase == .listening else {
    await withCheckedContinuation { continuation in chat.finish { continuation.resume() } }
    return
  }
  capture.finalText.withLock { $0 = "Another question" }
  capture.update(.speechEnded(nil))
  try await recoveryWait { await harness.reasoning.requests == 2 && !chat.isWorking }
  #expect(
    chat.messages.filter { $0.role == .user }.map(\.text)
      == ["Tea instructions", "Another question"])
  #expect(await harness.voice.attempts.count == 2)
  #expect(await harness.voice.attempts.last?.phrases == ["Of course."])
  await withCheckedContinuation { continuation in chat.finish { continuation.resume() } }
}

private final class RecoveryCapture: ConversationCapture, Sendable {
  let update: @Sendable (AudioCaptureUpdate) -> Void
  let finalText = Mutex("")
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() { update(.capturing("Listening")) }
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    complete(completion)
  }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) { complete(completion) }
  private func complete(_ completion: @Sendable (AudioCaptureResult) -> Void) {
    let text = finalText.withLock { value in
      defer { value = "" }
      return value
    }
    completion(.init(transcript: text, recordingURL: nil, duration: 1, failure: nil))
  }
}

private actor RecoveryReasoning: ConversationResponding {
  enum Ending { case preempted, complete }
  let ending: Ending
  init(ending: Ending) { self.ending = ending }
  static let phrases = ["Heat the water.", "Add the tea leaves.", "Steep for three minutes."]
  private(set) var requests = 0
  private var waiting: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { waiting != nil }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  { try await streamReply(to: context, progress: progress, receive: { _ in }) }
  func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    requests += 1
    if requests > 1 {
      try await receive("Of course.")
      return .init(text: "Of course.")
    }
    for phrase in Self.phrases { try await receive(phrase + " ") }
    // This unfinished tail must never become replayed speech after inference cancellation.
    if ending == .preempted { try await receive("An unfinished") }
    await withCheckedContinuation { waiting = $0 }
    if ending == .preempted { throw CancellationError() }
    return .init(text: Self.phrases.joined(separator: " "))
  }
  func preempt() {
    waiting?.resume()
    waiting = nil
  }
}

private actor RecoveryVoice: ChatSpeechOutput {
  enum Replay { case immediate, suspended }
  let replay: Replay
  init(replay: Replay) { self.replay = replay }
  struct Attempt: Sendable {
    let id: UUID
    var phrases: [String] = []
  }
  private(set) var attempts: [Attempt] = []
  private(set) var resumed = 0
  private var waiting: CheckedContinuation<Void, any Error>?
  private var holdsStops = false
  private var stopWaiters: [CheckedContinuation<Void, Never>] = []
  var isWaiting: Bool { waiting != nil }
  var isStopping: Bool { !stopWaiters.isEmpty }
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  )
    async throws -> String?
  { nil }
  func speakStream(
    _ request: ChatSpeechRequest, text: SpeechTextStream,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    #expect(waiting == nil, "The previous playback must drain before another attempt starts.")
    let index = attempts.count
    attempts.append(.init(id: request.id))
    while let phrase = try await text.next() {
      attempts[index].phrases.append(phrase)
      receive(.speaking(level: 0.5))
      if (index == 0 && attempts[index].phrases.count == 2)
        || (index == 1 && replay == .suspended && attempts[index].phrases.count == 1)
      {
        try await withCheckedThrowingContinuation { waiting = $0 }
      }
      receive(.utteranceFinished(phrase))
    }
    receive(.finished)
    return nil
  }
  func pause(id: UUID) {}
  func resume(id: UUID) { resumed += 1 }
  func holdStops() { holdsStops = true }
  func releaseStops() {
    holdsStops = false
    let pending = stopWaiters
    stopWaiters.removeAll()
    for waiter in pending { waiter.resume() }
  }
  func stop(id: UUID) async {
    guard attempts.last?.id == id else { return }
    if holdsStops { await withCheckedContinuation { stopWaiters.append($0) } }
    guard attempts.last?.id == id else { return }
    waiting?.resume(throwing: CancellationError())
    waiting = nil
  }
}

@MainActor private func recoveryWait(_ predicate: @MainActor () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await predicate()) {
    if ContinuousClock.now >= deadline { throw RecoveryTimeout() }
    try await Task.sleep(for: .milliseconds(5))
  }
}
private struct RecoveryTimeout: Error {}

@Test @MainActor private func chatContinuingAStoppedReplyWaitsForPlaybackAndDoesNotRepeatInference()
  async throws
{
  let events = Mutex<[DiagnosticEvent]>([])
  let harness = RecoveryHarness(
    ending: .complete,
    diagnostics: DiagnosticSink { event in
      events.withLock { $0.append(event) }
    })
  let chat = harness.chat
  await chat.startTalk()
  try await recoveryWait { chat.phase == .listening }
  let capture = try #require(harness.capture())
  capture.finalText.withLock { $0 = "Tea instructions" }
  capture.update(.speechEnded(nil))
  try await recoveryWait {
    let waiting = await harness.reasoning.isWaiting
    return await harness.voice.isWaiting && waiting
  }
  await harness.voice.holdStops()
  chat.interrupt()
  await harness.reasoning.preempt()
  try await recoveryWait {
    let stopping = await harness.voice.isStopping
    return chat.canContinueSpeaking && stopping
  }
  let messages = chat.messages
  #expect(messages.last?.spokenText == RecoveryReasoning.phrases[0])
  chat.continueSpeaking()
  chat.continueSpeaking()  // Repeated clicks cannot start a competing replay.
  #expect(chat.phase == .preparingVoice)
  #expect(await harness.voice.attempts.count == 1)
  await harness.voice.releaseStops()
  try await recoveryWait { await harness.voice.attempts.count == 2 && !chat.isWorking }
  #expect(chat.messages.map(\.id) == messages.map(\.id))
  #expect(chat.messages.map(\.text) == messages.map(\.text))
  #expect(chat.messages.last?.spokenText == RecoveryReasoning.phrases.joined(separator: " "))
  #expect(await harness.reasoning.requests == 1)
  #expect(chat.failure == nil && !chat.canContinueSpeaking)
  let diagnostics = events.withLock { $0 }
  #expect(diagnostics.contains { $0.action == .cancelled && $0.reason == .userStop })
  #expect(
    diagnostics.contains { $0.action == .recoveryStarted && $0.reason == .explicitContinuation })
  #expect(diagnostics.contains { $0.action == .milestone && $0.metric == .firstText })
  #expect(
    diagnostics.contains {
      $0.area == .synthesis && $0.action == .started && $0.relatedOperation != nil
        && $0.operation != $0.relatedOperation
    })
  let encoded = String(decoding: try JSONEncoder().encode(diagnostics), as: UTF8.self)
  #expect(!encoded.contains("Tea instructions") && !encoded.contains("Heat the water"))
  chat.finish {}
}
