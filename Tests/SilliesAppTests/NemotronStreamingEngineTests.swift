import SilliesSpeech
import Testing

@testable import SilliesSpeechNemotron

@Test func speechRecognitionNemotronReplayUsesTheNativeEncoderContext() {
  let native = NemotronRecognitionConfiguration.native(language: .auto)
  #expect(
    NemotronRecognitionConfiguration.channel.boundaryReplayDuration == Double(
      native.leftFrames * native.frameSamples) / Double(native.sampleRate))
}

@Test func speechRecognitionNemotronRestartsOnGainChangesAndNewSources() async throws {
  let decoder = RecordingNemotronDecoder()
  let engine = NemotronStreamingEngine(decoder: decoder)
  _ = try await engine.transcribe(nemotronRequest([0.01]))
  _ = try await engine.transcribe(nemotronRequest([0.01, 0.01]))
  _ = try await engine.transcribe(nemotronRequest([0.01, 0.01, 0.4]))
  var final = nemotronRequest([0.01, 0.01, 0.4])
  final.window = .init(start: 0, phase: .complete)
  _ = try await engine.transcribe(final)
  try await engine.resetForReuse()
  _ = try await engine.transcribe(nemotronRequest([0.01]))
  let inputs = await decoder.inputs
  #expect(inputs == [[0.02], [0.02], [0.01, 0.01, 0.4], [], [0.02]])
  let phases = await decoder.phases
  #expect(phases == [.partial, .partial, .partial, .complete, .partial])
  let resets = await decoder.resets
  #expect(resets == 4)
}

@Test func speechRecognitionNemotronReplaysFailedNativeInputBeforeContinuing() async throws {
  let decoder = RecordingNemotronDecoder(behavior: .failFirst)
  let engine = NemotronStreamingEngine(decoder: decoder)
  let request = nemotronRequest([0.01, 0.01])
  do {
    _ = try await engine.transcribe(request)
    Issue.record("Expected the injected decoder failure")
  } catch RecordingNemotronDecoder.Failure.injected {}
  _ = try await engine.transcribe(request)
  let inputs = await decoder.inputs
  #expect(inputs == [[0.02, 0.02], [0.02, 0.02]])
  let resets = await decoder.resets
  #expect(resets == 2)
}

@Test func speechRecognitionNemotronPositionsContinuousNativeWordsInTheCurrentWindow() async throws
{
  let decoder = RecordingNemotronDecoder(
    result: .init(words: [.init(text: "word", start: 11.4, end: 11.8)]))
  let engine = NemotronStreamingEngine(decoder: decoder)
  var first = nemotronRequest([Float](repeating: 0.01, count: 12 * 16_000))
  first.window = .init(start: 0, phase: .boundary)
  _ = try await engine.transcribe(first)
  var second = nemotronRequest([Float](repeating: 0.01, count: 3 * 16_000))
  second.window = .init(start: 10, phase: .complete)
  let result = try await engine.transcribe(second)
  let word = try #require(result.words.first)
  #expect(abs(word.start - 1.4) < 0.0001 && abs(word.end - 1.8) < 0.0001)
  let resets = await decoder.resets
  #expect(resets == 1)
  let inputs = await decoder.inputs
  #expect(inputs.last?.count == 16_000)
}

@Test func speechRecognitionNemotronCancellationDiscardsUncommittedDecoderProgress() async throws {
  let decoder = RecordingNemotronDecoder(behavior: .suspendFirst)
  let engine = NemotronStreamingEngine(decoder: decoder)
  let request = nemotronRequest([0.01, 0.01])
  let first = Task { try await engine.transcribe(request) }
  await decoder.waitUntilSuspended()
  first.cancel()
  await decoder.resume()
  do {
    _ = try await first.value
    Issue.record("Cancelled native inference returned a result")
  } catch is CancellationError {}
  _ = try await engine.transcribe(request)
  let inputs = await decoder.inputs
  #expect(inputs == [[0.02, 0.02], [0.02, 0.02]])
}

private func nemotronRequest(_ samples: [Float]) -> SpeechWindowRequest {
  var request = SpeechWindowRequest(samples: samples, language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  return request
}

private actor RecordingNemotronDecoder: NemotronDecoding {
  enum Behavior { case ordinary, failFirst, suspendFirst }
  enum Failure: Error { case injected }
  private let behavior: Behavior
  private let result: SpeechWindowResult
  private var suspension: CheckedContinuation<Void, Never>?
  private var observers: [CheckedContinuation<Void, Never>] = []
  private(set) var inputs: [[Float]] = []
  private(set) var phases: [SpeechWindowPosition.Phase] = []
  private(set) var resets = 0
  init(behavior: Behavior = .ordinary, result: SpeechWindowResult = .init(words: [])) {
    self.behavior = behavior
    self.result = result
  }

  func decode(_ samples: [Float], phase: SpeechWindowPosition.Phase) async throws
    -> SpeechWindowResult
  {
    inputs.append(samples)
    phases.append(phase)
    if inputs.count == 1 {
      switch behavior {
      case .ordinary: break
      case .failFirst: throw Failure.injected
      case .suspendFirst:
        await withCheckedContinuation { continuation in
          suspension = continuation
          for observer in observers { observer.resume() }
          observers.removeAll()
        }
      }
    }
    return result
  }

  func reset() { resets += 1 }
  func waitUntilSuspended() async {
    if suspension != nil { return }
    await withCheckedContinuation { observers.append($0) }
  }
  func resume() {
    suspension?.resume()
    suspension = nil
  }
}
