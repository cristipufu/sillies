import AVFoundation
import Foundation
import NaturalLanguage
import SilliesCore
import Testing

@testable import SilliesApp

private final class SpeechFixtureOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var transcript = SpeechTranscript()
  private var failures: [String] = []
  func receive(_ phrase: SpeechPhrase) {
    lock.withLock {
      transcript.receive(phrase, source: .application, elapsed: phrase.startTime ?? 0)
    }
  }
  func failed(_ error: String) { lock.withLock { failures.append(error) } }
  var snapshot: (String, [String]) { lock.withLock { (transcript.text, failures) } }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_LOCAL_AI_CHECK"] == "1"))
func localNotesHonorTheSelectedLanguage() async {
  let notice = await LocalReasoningService.shared.availabilityNotice(localeIdentifier: "fr-FR")
  guard notice == nil else { return }
  let result = await LocalReasoningService.shared.notes(
    for: "We agreed to ship the report on Friday. Alex will review the draft tomorrow.",
    kind: .record, fallback: "Fixture", localeIdentifier: "fr-FR")
  print("FRENCH NOTES: \(result.summary) | \(result.actions)")
  #expect(NLLanguageRecognizer.dominantLanguage(for: result.summary) == .french)
  #expect(result.actions.contains { $0.localizedCaseInsensitiveContains("vendredi") })
  #expect(
    result.actions.contains { $0.contains("Alex") && $0.localizedCaseInsensitiveContains("demain") }
  )
}

/// Opt-in: feeds a generated speech file, never records the room or an application.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_LOCAL_AI_CHECK"] == "1"))
@MainActor func localModelsAndAACEncodingKeepAllInteractionPathsWithinBudget() async throws {
  try await exerciseLocalModels {
    try windowDragSmoothnessBudgetAndSinglePassPlacement()
    try windowResizeSmoothnessBudgetAndCompactionQuantization()
    try windowSwitchSmoothnessBudgetAndZeroFlickerAppTransition()
    try companionDragSmoothnessBudgetAndUnclippedMaskStability(characterID: "pogo")
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_LOCAL_AI_CHECK"] == "1"))
@MainActor func localSpeechHandlesFrequentCallbacksWithoutLosingAudio() async throws {
  try await exerciseLocalModels {}
}

@MainActor private func exerciseLocalModels(interaction: () throws -> Void) async throws {
  let fixturePath = try #require(ProcessInfo.processInfo.environment["SILLIES_SPEECH_FIXTURE"])
  let outputs = [SpeechFixtureOutput(), SpeechFixtureOutput()]
  var channels: [any LocalSpeechChannel] = []
  for output in outputs {
    channels.append(
      try await LocalSpeechFactory.make(
        language: fixtureEnglish,
        output: { output.receive($0) }, failure: { output.failed($0) }))
  }
  let activeChannels = channels
  let source =
    "We agreed to ship the report on Friday. Alex will review the draft tomorrow. The owner of the customer follow-up is still undecided."
  let notes = Task.detached {
    await LocalReasoningService.shared.notes(for: source, kind: .participate, fallback: "Fixture")
  }
  let notice = await LocalReasoningService.shared.availabilityNotice()
  print("LOCAL AI AVAILABILITY: \(notice ?? "available")")
  let speech = Task.detached(priority: .utility) {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixturePath))
    let recording = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sillies-ai-check-\(UUID().uuidString).m4a")
    defer { removeTestFile(at: recording) }
    let writer = try AudioRecordingWriter(destination: recording)
    for _ in 0..<3 {
      file.framePosition = 0
      while file.framePosition < file.length {
        let buffer = try #require(
          AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * 0.01)))
        try file.read(into: buffer)
        try writer.append(buffer)
        for channel in activeChannels { channel.append(buffer) }
        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / buffer.format.sampleRate))
      }
    }
    _ = try writer.finish()
    for channel in activeChannels {
      await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    }
  }
  try interaction()
  try await speech.value
  let result = await notes.value
  print("LOCAL NOTES: \(result.summary) | \(result.actions) | \(result.notice)")
  #expect(!result.summary.isEmpty)
  if notice == nil {
    #expect(result.actions.contains { $0.localizedCaseInsensitiveContains("report") })
    #expect(
      result.actions.contains {
        $0.localizedCaseInsensitiveContains("Alex")
          && $0.localizedCaseInsensitiveContains("tomorrow")
      })
  }
  for output in outputs {
    let (text, failures) = output.snapshot
    print("LOCAL SPEECH: \(text)")
    #expect(failures.isEmpty)
    #expect(text.localizedCaseInsensitiveContains("report"))
    #expect(text.localizedCaseInsensitiveContains("Friday"))
    #expect(text.lowercased().components(separatedBy: "report").count - 1 == 3)
    #expect(text.lowercased().components(separatedBy: "alex").count - 1 == 3)
    #expect(text.lowercased().components(separatedBy: "undecided").count - 1 == 3)
  }
}
