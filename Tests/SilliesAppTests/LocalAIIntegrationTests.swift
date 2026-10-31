import AVFoundation
import Foundation
import NaturalLanguage
import SilliesAudioTestSupport
import SilliesCore
import SilliesDiarizationNemotron
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechApple
import SilliesSpeechParakeet
import SilliesSpeechWhisper
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesAudio

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

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_DOWNLOADED_STT_CHECK"] == "1"))
@MainActor func downloadedSpeechModelsKeepAllInteractionPathsWithinBudget() async throws {
  try await exerciseLocalModels {
    try windowDragSmoothnessBudgetAndSinglePassPlacement()
    try windowResizeSmoothnessBudgetAndCompactionQuantization()
    try windowSwitchSmoothnessBudgetAndZeroFlickerAppTransition()
    try companionDragSmoothnessBudgetAndUnclippedMaskStability(characterID: "pogo")
    try playfulTravelUsesBoundedNativeFrameWork()
    try playfulSharedTravelUsesBoundedNativeFrameWork()
  }
}

private func downloadedRuntime() async throws -> SpeechRuntimeRegistry.Runtime? {
  try await downloadedRuntime(id: ProcessInfo.processInfo.environment["SILLIES_STT_MODEL"])
}

private func downloadedSpeakerRuntime() async throws -> SpeechRuntimeRegistry.Runtime? {
  try await downloadedRuntime(id: ProcessInfo.processInfo.environment["SILLIES_DIARIZATION_MODEL"])
}

private func downloadedRuntime(id: String?) async throws -> SpeechRuntimeRegistry.Runtime? {
  let runtime: SpeechRuntimeRegistry.Runtime?
  if let id,
    let root = ProcessInfo.processInfo.environment["SILLIES_STT_STORE"]
  {
    let registry = try SpeechRuntimeRegistry(
      store: ModelStore(root: URL(fileURLWithPath: root)),
      providers: [WhisperSpeechProvider(), ParakeetSpeechProvider()],
      diarizationProviders: [NemotronDiarizationProvider()])
    runtime = try await registry.prepare(id)
  } else {
    runtime = nil
  }
  return runtime
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_STT_PREPARE_ONLY"] == "1"))
func prepareDownloadedSpeechModelForIntegration() async throws {
  let runtime = try await downloadedRuntime()
  let speakers = try await downloadedSpeakerRuntime()
  #expect(runtime != nil)
  withExtendedLifetime((runtime, speakers)) {}
}

@MainActor private func exerciseLocalModels(interaction: () throws -> Void) async throws {
  let fixturePath = try #require(ProcessInfo.processInfo.environment["SILLIES_SPEECH_FIXTURE"])
  let runtime = try await downloadedRuntime()
  let speakerRuntime = try await downloadedSpeakerRuntime()
  let speakerFrames = Mutex(0)
  let outputs = [SpeechFixtureOutput(), SpeechFixtureOutput()]
  var channels: [any LocalSpeechChannel] = []
  for output in outputs {
    let request = SpeechChannelRequest(
      language: runtime == nil ? fixtureEnglish : .automatic,
      output: { output.receive($0) }, failure: { output.failed($0) })
    if let runtime {
      channels.append(try await runtime.makeChannel(request))
    } else {
      channels.append(
        try await AppleSpeechProvider.makeChannel(
          language: request.language, output: request.output, failure: request.failure))
    }
    if let speakerRuntime {
      channels.append(
        try await speakerRuntime.makeChannel(
          .init(
            output: { batch in speakerFrames.withLock { $0 += batch.frameCount } },
            failure: { output.failed($0) })))
    }
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
  if runtime != nil { try await Task.sleep(for: .seconds(3)) }
  try interaction()
  try await speech.value
  withExtendedLifetime((runtime, speakerRuntime)) {}
  if speakerRuntime != nil { #expect(speakerFrames.withLock { $0 } > 0) }
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
