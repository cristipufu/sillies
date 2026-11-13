import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesCore
import SilliesDiarizationNemotron
import SilliesModelStore
import SilliesReasoning
import SilliesSpeech
import SilliesSpeechApple
import SilliesSpeechNemotron
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
func localMeetingExcerptsPreserveSourceLanguageAndTasks() async {
  let notice = await LocalReasoningService(backend: AppleReasoningBackend()).availabilityNotice(
    localeIdentifier: "en")
  guard notice == nil else { return }
  let source = "We agreed to ship the report on Friday. Alex will review the draft tomorrow."
  let result = await LocalReasoningService(backend: AppleReasoningBackend()).notes(
    for: .init(source: source, kind: .record, fallback: "Fixture", localeIdentifier: "fr-FR"))
  print("SOURCE EXCERPTS: \(result.summary) | \(result.actions)")
  #expect(result.source == .extracted && result.notice.isEmpty)
  #expect(result.summary.contains("We agreed to ship the report on Friday."))
  for line in result.summary.split(separator: "\n") where line.hasPrefix("• ") {
    #expect(source.contains(line.dropFirst("• ".count)))
  }
  #expect(result.actions.allSatisfy { source.contains($0) })
  #expect(result.actions.contains { $0.contains("Alex") && $0.contains("tomorrow") })
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
      providers: [WhisperSpeechProvider(), ParakeetSpeechProvider(), NemotronSpeechProvider()],
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
    await LocalReasoningService(backend: AppleReasoningBackend()).notes(
      for: .init(source: source, kind: .participate, fallback: "Fixture"))
  }
  let notice = await LocalReasoningService(backend: AppleReasoningBackend()).availabilityNotice()
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
    #expect(result.summary.localizedCaseInsensitiveContains("report"))
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
