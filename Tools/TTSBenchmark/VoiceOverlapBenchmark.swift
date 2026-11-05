import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS
import SilliesTextModels

/// Controlled resource-contention probe. Fixed speech is not an end-to-end conversational answer.
struct VoiceOverlapBenchmark {
  private let textManifest: TextModelManifest
  private let voiceManifest: TTSModelManifest
  private let text: TextModelRegistry
  private let voice: TTSModelRegistry
  private let directory: URL
  private enum Schedule: String, Codable { case sequential, overlapping }
  private enum Completion: Sendable {
    case text
    case voice(VoiceProfileSamples.Report)
  }
  private struct Observation: Codable {
    let schedule: Schedule
    let firstTextSeconds: Double
    let textSeconds: Double
    let synthesisRequestedSeconds: Double
    let totalSeconds: Double
    let text: String
    let audio: VoiceProfileSamples.Report
  }
  private struct Report: Codable {
    let textModel: String
    let textRevision: String
    let voiceModel: String
    let voiceRevision: String
    let observations: [Observation]
  }

  init(arguments: [String]) throws {
    let models = try VoiceBenchmarkModels(arguments: arguments)
    self.textManifest = models.textManifest
    self.voiceManifest = models.voiceManifest
    self.directory = models.directory
    self.text = models.text
    self.voice = models.voice
  }

  func run() async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var observations: [Observation] = []
    do {
      // Preserve cold preparation separately, then alternate order with both helpers resident.
      let schedules: [Schedule] = [
        .sequential, .sequential, .overlapping, .overlapping, .sequential,
      ]
      for (index, schedule) in schedules.enumerated() {
        observations.append(try await measure(schedule, index: index))
        let report = Report(
          textModel: textManifest.modelID, textRevision: textManifest.revision,
          voiceModel: voiceManifest.modelID, voiceRevision: voiceManifest.revision,
          observations: observations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
          to: directory.appendingPathComponent("overlap.json"), options: .atomic)
      }
      await stop()
    } catch {
      await stop()
      throw error
    }
  }

  private func measure(_ schedule: Schedule, index: Int) async throws -> Observation {
    let turn = UUID()
    let started = ProcessInfo.processInfo.systemUptime
    let timing = VoiceOverlapTiming(started: started)
    let samples = VoiceProfileSamples(delivery: .paced, startedAt: started)
    let (events, admission) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    guard let selectedVoice = voiceManifest.model.voices.first else {
      throw TTSError.unsupportedVoice
    }
    let speech = SpeechSynthesisRequest(
      text: "Hello there. I can start speaking before the whole reply is ready.",
      voiceID: selectedVoice.id, language: "en", conversationID: turn)
    let request = TextGenerationRequest(
      instructions: "Answer in plain text with four short sentences.",
      prompt: "Describe how a rainy-day walk can be relaxing.", maximumTokens: 192,
      style: .conversation
    ).inConversation(turn)
    let audio = try await withThrowingTaskGroup(of: Completion.self) { group in
      group.addTask {
        defer { admission.finish() }
        let output = try await text.stream(request, using: textManifest) { delta in
          if await timing.received(delta), schedule == .overlapping { admission.yield(()) }
        }
        try await timing.finished(output.text)
        admission.yield(())
        return .text
      }
      group.addTask {
        var admitted = false
        for await _ in events {
          admitted = true
          break
        }
        try Task.checkCancellation()
        guard admitted else { throw CancellationError() }
        await timing.synthesisRequested()
        try await voice.synthesize(speech, using: voiceManifest) { try await samples.append($0) }
        return .voice(await samples.report())
      }
      var audio: VoiceProfileSamples.Report?
      do {
        while let completion = try await group.next() {
          if case .voice(let report) = completion { audio = report }
        }
      } catch {
        group.cancelAll()
        throw error
      }
      guard let audio else { throw TTSError.invalidAudio }
      return audio
    }
    guard !audio.chunks.isEmpty, audio.firstNonSilentPCM != nil,
      let first = await timing.first, let completed = await timing.completed,
      let synthesisRequested = await timing.voiceStarted
    else { throw TTSError.invalidAudio }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    try await samples.writeAudio(to: directory.appendingPathComponent("request-\(index).wav"))
    return await Observation(
      schedule: schedule, firstTextSeconds: first, textSeconds: completed,
      synthesisRequestedSeconds: synthesisRequested, totalSeconds: elapsed,
      text: timing.text, audio: audio)
  }

  private func stop() async {
    await text.stop()
    await voice.stop()
  }
}
