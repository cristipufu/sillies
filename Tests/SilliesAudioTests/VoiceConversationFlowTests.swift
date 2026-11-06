import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesChat
import SilliesCore
import SilliesSpeech
import SilliesTTS
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesAudio
@testable import SilliesReasoning

/// Real capture queue, AEC/VAD, finalization, conversation/tool loop and phrase delivery.
/// Recorded synthetic PCM and scripted model outputs isolate lifecycle from model accuracy.
@Test @MainActor func continuousVoiceFlowsThroughThreeTurnsWithoutRestartingCapture() async throws {
  let input = VoiceFlowInput()
  let backend = VoiceFlowBackend()
  let search = VoiceFlowSearch()
  let voice = VoiceFlowOutput()
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [search], turns: .init())
  let chat = ChatSession(
    companionName: "Pogo", profile: .init(personality: "Curious", languageIdentifier: "en"),
    services: .init(
      captureFactory: input.makeCapture,
      loadLanguages: { .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)]) },
      conversation: service, speech: voice,
      deliver: { action in Task { @MainActor in action() } }, history: .transient))
  chat.startListening()
  try await voiceFlowWait { chat.phase == .listening }
  let statements = ["Find my tea note", "Actually, make that mint tea", "Thanks"]
  let origin = ProcessInfo.processInfo.systemUptime - 30
  for (index, statement) in statements.enumerated() {
    input.nextWords.withLock { $0 = statement }
    let offset = origin + Double(index * 3)
    try await input.feed(.speech, at: offset)
    // Ending is caused by the real VAD receiving silence, never finishListening() in this test.
    try await input.feed(.silence, at: offset + 1)
    try await input.feed(.silence, at: offset + 2)
    do {
      try await voiceFlowWait {
        chat.messages.filter { $0.role == .companion }.count == index + 1 && !chat.isWorking
      }
    } catch {
      Issue.record(
        "Turn \(index): phase \(chat.phase), failure \(String(describing: chat.failure)), channels \(input.channels.withLock { $0 }), events \(input.events.withLock { $0 })"
      )
      throw error
    }
    #expect(chat.phase == .listening)
    #expect(chat.failure == nil)
    #expect(chat.messages.last?.spokenText == chat.messages.last?.text)
    #expect(chat.endpointLatency != nil && chat.recognitionFinalizedLatency != nil)
    #expect(chat.firstTextLatency != nil && chat.firstAudioLatency != nil)
  }
  #expect(chat.messages.filter { $0.role == .user }.map(\.text) == statements)
  #expect(await search.calls == 1)
  #expect(await backend.prompts == statements)
  #expect(input.starts.withLock { $0 } == 1)
  #expect(input.channels.withLock { $0 } == 3)
  #expect(await voice.phrases.count == 3)
  await withCheckedContinuation { continuation in chat.finish { continuation.resume() } }
  #expect(input.stops.withLock { $0 } == 1)
  #expect(chat.phase == .finished)
}

private final class VoiceFlowInput: MicrophoneCapture {
  let starts = Mutex(0)
  let stops = Mutex(0)
  let channels = Mutex(0)
  let nextWords = Mutex("")
  let events = Mutex<[String]>([])
  private let receiver = Mutex<AudioCaptureInputQueue.Receiver?>(nil)
  private let queue = DispatchQueue(label: "sillies.test.whole-voice-flow")
  func makeCapture(
    configuration: AudioCaptureConfiguration,
    update: @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) -> any ConversationCapture {
    VoiceConversationCapture(
      configuration: configuration, reference: VoicePlaybackReference(),
      resources: .init(
        audio: .init(
          queue: queue,
          microphone: { [self] receive, _ in
            receiver.withLock { $0 = receive }
            return self
          },
          speech: { [self] _, output, _ in
            channels.withLock { $0 += 1 }
            return VoiceFlowRecognizer(words: nextWords.withLock { $0 }, output: output)
          }), warmSpeech: {}),
      update: { [self] event in
        switch event {
        case .transcript: break
        default: events.withLock { $0.append(String(describing: event)) }
        }
        update(event)
      })
  }
  func start() async throws -> String {
    starts.withLock { $0 += 1 }
    return "Recorded fixture"
  }
  func stop(completion: @escaping @Sendable () -> Void) {
    stops.withLock { $0 += 1 }
    receiver.withLock { $0 = nil }
    completion()
  }
  func feed(_ signal: ConversationSignal, at time: TimeInterval) async throws {
    receiver.withLock { $0 }?(try conversationAudio(signal, at: time))
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  }
}

private final class VoiceFlowRecognizer: LocalSpeechChannel {
  private let words: String
  private let output: LocalSpeechFactory.Output
  private let frames = Mutex(0)
  init(words: String, output: @escaping LocalSpeechFactory.Output) {
    self.words = words
    self.output = output
  }
  func append(_ buffer: AVAudioPCMBuffer) { frames.withLock { $0 += Int(buffer.frameLength) } }
  func finish(completion: @escaping @Sendable () -> Void) {
    #expect(frames.withLock { $0 } >= 4_800)
    output(.init(text: words, isFinal: true))
    completion()
  }
  func cancel() {}
}

private actor VoiceFlowBackend: ConversationBackend {
  nonisolated let contextWindowTokens = 4_096
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  private(set) var prompts: [String] = []
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    try ConversationTokenEstimate.count(request)
  }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    throw TextModelError.invalidResponse
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    prompts.append(request.prompt)
    if prompts.count == 1 {
      return try await tools.invoke(
        .init(id: "tea", name: "search_vault", arguments: Data("{}".utf8)))
    }
    return prompts.count == 2 ? "Mint tea, understood." : "You're welcome."
  }
}

private actor VoiceFlowSearch: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "search_vault", description: "Search notes", parameters: [])
  nonisolated let activity = "Searching"
  private(set) var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(text: "The saved note recommends jasmine tea.")
  }
}

private actor VoiceFlowOutput: ChatSpeechOutput {
  private(set) var phrases: [String] = []
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) -> String? {
    phrases.append(request.text)
    receive(.milestone(.firstPCM))
    receive(.speaking(level: 0.4))
    receive(.milestone(.audibleOutput(ProcessInfo.processInfo.systemUptime)))
    return nil
  }
  func stop(id: UUID) {}
  func pause(id: UUID) {}
  func resume(id: UUID) {}
}

@MainActor private func voiceFlowWait(_ predicate: @MainActor () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !predicate() {
    if .now >= deadline { throw VoiceFlowTimeout() }
    try await Task.sleep(for: .milliseconds(5))
  }
}
private struct VoiceFlowTimeout: Error {}
