import Foundation
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesTTS
import SilliesTextModels

/// Production reply generation and phrase assembly, with a silent playback-rate sink.
/// Capture, recognition and physical device presentation are intentionally outside this probe.
struct VoiceConversationBenchmark {
  private enum Order: String, Codable {
    case currentFirst = "current-first"
    case earlyFirst = "early-first"
    var openings: [Opening] {
      // Separate warmup from one matched pair; reverse order in the next bounded process.
      [.current] + (self == .currentFirst ? [.current, .early] : [.early, .current])
    }
  }
  private enum Opening: String, Codable {
    case current, early
    var delay: Duration {
      self == .current ? ChatTurnStream.defaultOpeningPhraseDelay : .milliseconds(120)
    }
  }
  private struct Observation: Codable {
    let opening: Opening
    let text: String
    let spokenPhrases: [String]
    let firstTextSeconds: Double
    let textSeconds: Double
    let synthesisRequestedSeconds: Double
    let audio: VoiceProfileSamples.Report
  }
  private struct Report: Codable {
    let textModel: String
    let textRevision: String
    let voiceModel: String
    let voiceRevision: String
    let order: Order
    let observations: [Observation]
  }
  private let models: VoiceBenchmarkModels
  private let order: Order
  init(arguments: [String]) throws {
    guard (5...6).contains(arguments.count),
      let order = Order(rawValue: arguments.count == 6 ? arguments[5] : Order.currentFirst.rawValue)
    else { throw TTSError.invalidRequest }
    models = try VoiceBenchmarkModels(arguments: Array(arguments.prefix(5)))
    self.order = order
  }

  func run() async throws {
    try FileManager.default.createDirectory(at: models.directory, withIntermediateDirectories: true)
    let textLifetime = TextModelLifetime()
    let voiceLifetime = SpeechModelLifetime()
    await models.text.retain(for: textLifetime)
    await models.voice.retain(for: voiceLifetime)
    var observations: [Observation] = []
    do {
      for opening in order.openings {
        observations.append(try await measure(opening))
        let report = Report(
          textModel: models.textManifest.modelID,
          textRevision: models.textManifest.revision,
          voiceModel: models.voiceManifest.modelID, voiceRevision: models.voiceManifest.revision,
          order: order, observations: observations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
          to: models.directory.appendingPathComponent("spoken-answer.json"), options: .atomic)
      }
      await textLifetime.end()
      await voiceLifetime.end()
      await models.stop()
    } catch {
      await textLifetime.end()
      await voiceLifetime.end()
      await models.stop()
      throw error
    }
  }

  private func measure(_ opening: Opening) async throws -> Observation {
    let started = ProcessInfo.processInfo.systemUptime
    let timing = VoiceOverlapTiming(started: started)
    let samples = VoiceProfileSamples(delivery: .paced, startedAt: started)
    let stream = ChatTurnStream(receive: { _ in }, openingPhraseDelay: opening.delay)
    let backend = DownloadedReasoningBackend(
      manifest: models.textManifest, store: models.textStore, registry: models.text)
    let conversation = LocalConversationService(
      resolveBackend: { backend }, tools: [], turns: .init())
    let context = ChatContext(
      companionName: "Pogo",
      profile: .init(personality: "Warm and curious.", languageIdentifier: "en"),
      messages: [
        .init(
          role: .user,
          text: "In three short sentences, explain why rainbows have different colours.")
      ]
    )
    .presented(as: .talk)
    let voice = Task {
      try await synthesize(stream.speech, turn: context.turnID, timing: timing, samples: samples)
    }
    do {
      let reply = try await conversation.streamReply(
        to: context, progress: { _ in },
        receive: { delta in
          _ = await timing.received(delta)
          try await stream.append(delta)
        })
      try await timing.finished(reply.text)
      try await stream.finish(reply.text)
      let phrases = try await voice.value
      try Self.validateDelivery(reply.text, phrases: phrases)
      guard let first = await timing.first, let complete = await timing.completed,
        let synthesis = await timing.voiceStarted
      else { throw TTSError.invalidAudio }
      return await .init(
        opening: opening, text: reply.text, spokenPhrases: phrases,
        firstTextSeconds: first, textSeconds: complete,
        synthesisRequestedSeconds: synthesis, audio: samples.report())
    } catch {
      voice.cancel()
      await stream.cancel()
      _ = await voice.result
      throw error
    }
  }

  private func synthesize(
    _ stream: SpeechTextStream, turn: UUID, timing: VoiceOverlapTiming, samples: VoiceProfileSamples
  ) async throws -> [String] {
    guard let selected = models.voiceManifest.model.voices.first else {
      throw TTSError.unsupportedVoice
    }
    guard try await stream.waitForTextStart() else { return [] }
    _ = try await models.voice.prepareVoiceIfPossible(
      .init(id: selected.id, language: "en"), using: models.voiceManifest, conversationID: turn)
    var phrases: [String] = []
    while let phrase = try await stream.next() {
      if phrases.isEmpty { await timing.synthesisRequested() }
      try await models.voice.synthesize(
        .init(text: phrase, voiceID: selected.id, language: "en", conversationID: turn),
        using: models.voiceManifest
      ) { try await samples.append($0) }
      phrases.append(phrase)
    }
    return phrases
  }

  static func validateDelivery(_ text: String, phrases: [String]) throws {
    func words(_ value: String) -> [Substring] { value.split(whereSeparator: \.isWhitespace) }
    guard !phrases.isEmpty, words(text) == words(phrases.joined(separator: " ")) else {
      throw TTSError.unavailable("Spoken phrases do not match the generated answer.")
    }
  }
}
