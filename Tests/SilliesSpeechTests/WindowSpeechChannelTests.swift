import AVFoundation
import Foundation
import SilliesCore
import Synchronization
import XCTest

@testable import SilliesSpeech

final class WindowSpeechChannelTests: XCTestCase, @unchecked Sendable {
  func testFailureDuringFinalDrainIsReportedBeforeCompletion() async throws {
    let events = Mutex<[String]>([])
    let owner = Mutex<WindowSpeechChannel?>(nil)
    let drained = expectation(description: "Failed drain completes")
    let channel = try WindowSpeechChannel(
      engine: FailingWindowEngine(),
      request: .init(
        language: .automatic, output: { _ in },
        failure: { _ in
          events.withLock { $0.append("failed") }
          let channel = owner.withLock { $0 }
          channel?.finish {
            events.withLock { $0.append("reentrant finish") }
            drained.fulfill()
          }
          events.withLock { $0.append("failure reported") }
        }))
    owner.withLock { $0 = channel }
    defer { owner.withLock { $0 = nil } }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][index] = 0.1 }
    channel.append(buffer)
    channel.finish {
      events.withLock { $0.append("finished") }
    }
    await fulfillment(of: [drained], timeout: 2)
    XCTAssertEqual(
      events.withLock { $0 }, ["failed", "failure reported", "finished", "reentrant finish"])
    channel.cancel()
  }
}

private actor FailingWindowEngine: SpeechWindowEngine {
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    throw SpeechError.unavailable("Fixture recognition failure")
  }
}

extension WindowSpeechChannelTests {
  func testUnchangedFinalWindowReusesOnlyEnginesThatDeclareCompleteDrafts() async throws {
    for policy in [SpeechFinalizationPolicy.decode, .reuseUnchangedDraft] {
      let draft = expectation(description: "Draft delivered")
      let finished = expectation(description: "Final delivered")
      let engine = CountingWindowEngine(policy: policy)
      let phrases = Mutex<[SpeechPhrase]>([])
      let measurements = Mutex<[SpeechInferenceMeasurement]>([])
      let windows = Mutex<[SpeechWindowMeasurement]>([])
      var request = SpeechChannelRequest(
        language: .automatic,
        output: { phrase in
          phrases.withLock { $0.append(phrase) }
          if !phrase.isFinal { draft.fulfill() }
        }, failure: { message in XCTFail(message) })
      request.measureWindow = { window in windows.withLock { $0.append(window) } }
      request.measureInference = { measurement in measurements.withLock { $0.append(measurement) } }
      let channel = try WindowSpeechChannel(engine: engine, request: request)
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
      buffer.frameLength = buffer.frameCapacity
      for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][index] = 0.1 }
      channel.append(buffer)
      await fulfillment(of: [draft], timeout: 2)
      channel.finish { finished.fulfill() }
      await fulfillment(of: [finished], timeout: 2)
      let count = await engine.count
      XCTAssertEqual(count, policy == .decode ? 2 : 1)
      XCTAssertEqual(windows.withLock { $0.count }, 2)
      XCTAssertEqual(windows.withLock { $0.first?.completion }, .draft)
      XCTAssertEqual(windows.withLock { $0.last?.completion }, .session)
      XCTAssertEqual(measurements.withLock { $0.count }, count)
      XCTAssertEqual(measurements.withLock { $0.first?.start }, 0)
      XCTAssertEqual(measurements.withLock { $0.first?.phase }, .partial)
      XCTAssertEqual(
        measurements.withLock { $0.last?.phase }, policy == .decode ? .complete : .partial)
      XCTAssertEqual(measurements.withLock { $0.reduce(0) { $0 + $1.sampleCount } }, 48_000 * count)
      XCTAssertTrue(phrases.withLock { $0.last?.isFinal == true })
      XCTAssertEqual(phrases.withLock { $0.last?.text }, "hello")
    }
  }
}

private actor CountingWindowEngine: SpeechWindowEngine {
  nonisolated let finalizationPolicy: SpeechFinalizationPolicy
  private(set) var count = 0
  init(policy: SpeechFinalizationPolicy) { finalizationPolicy = policy }
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    count += 1
    return .init(words: [.init(text: "hello", start: 0, end: 1)])
  }
}

extension WindowSpeechChannelTests {
  private struct BoundaryScenario {
    let purpose: SpeechRecognitionContext.Purpose
    let continuousMode: SpeechBoundaryPolicy.Mode
    var override: SpeechBoundaryPolicy.Mode?
    let shouldDecode: Bool
  }

  func testSharedWindowBoundaryDefaultsRespectCapturePurposeAndExplicitOverride() async throws {
    let scenarios: [BoundaryScenario] = [
      .init(purpose: .continuousTranscription, continuousMode: .adaptive, shouldDecode: true),
      .init(purpose: .continuousTranscription, continuousMode: .baseline, shouldDecode: false),
      .init(
        purpose: .continuousTranscription, continuousMode: .adaptive, override: .baseline,
        shouldDecode: false),
      .init(
        purpose: .continuousTranscription, continuousMode: .baseline, override: .adaptive,
        shouldDecode: true),
      .init(purpose: .shortUtterance, continuousMode: .adaptive, shouldDecode: false),
      .init(purpose: .shortUtterance, continuousMode: .baseline, shouldDecode: false),
      .init(
        purpose: .shortUtterance, continuousMode: .baseline, override: .adaptive, shouldDecode: true
      ),
    ]
    for cadence in [SpeechDecodeCadence.windowed, .streaming] {
      for scenario in scenarios { try await assertBoundaryDecision(scenario, cadence: cadence) }
    }
  }

  func testUnqualifiedModelsKeepBaselineBoundariesForContinuousCapture() async throws {
    let engine = CountingWindowEngine(policy: .decode)
    let model = WindowSpeechModel(engine: engine)
    var request = SpeechChannelRequest(
      language: .automatic, output: { _ in XCTFail("Unqualified quiet frame was promoted") },
      failure: { XCTFail($0) })
    request.context.purpose = .continuousTranscription
    let channel = try await model.makeChannel(request)
    defer { channel.cancel() }
    for energy: Float in [0, 0, 0, 0.0018, 0.0018, 0.0018] {
      channel.append(try audioFrame(energy: energy))
    }
    await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    let calls = await engine.count
    XCTAssertEqual(calls, 0)
  }

  private func assertBoundaryDecision(_ scenario: BoundaryScenario, cadence: SpeechDecodeCadence)
    async throws
  {
    let configuration = SpeechWindowConfiguration(
      cadence: cadence, continuousBoundaryMode: scenario.continuousMode)
    let engine = CountingWindowEngine(policy: .decode)
    var request = SpeechChannelRequest(
      language: .automatic, output: { _ in }, failure: { XCTFail($0) })
    request.context.purpose = scenario.purpose
    request.context.boundaryMode = scenario.override
    let channel: any LocalSpeechChannel
    switch cadence {
    case .windowed:
      channel = try await WindowSpeechModel(engine: engine, configuration: configuration)
        .makeChannel(request)
    case .streaming:
      channel = try WindowSpeechChannel(
        engine: engine, request: request, configuration: configuration)
    }
    defer { channel.cancel() }
    for energy: Float in [0, 0, 0, 0.0018, 0.0018, 0.0018] {
      channel.append(try audioFrame(energy: energy))
    }
    await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    let calls = await engine.count
    XCTAssertEqual(calls > 0, scenario.shouldDecode)
  }

  private func audioFrame(energy: Float) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][index] = energy }
    return buffer
  }
}

extension WindowSpeechChannelTests {
  func testAdaptiveInvalidAudioReportsOnceAndStillCompletesFinalization() async throws {
    let failures = Mutex(0)
    let engine = CountingWindowEngine(policy: .decode)
    var request = SpeechChannelRequest(
      language: .automatic, output: { _ in XCTFail("Invalid audio produced text") },
      failure: { _ in failures.withLock { $0 += 1 } })
    request.context.purpose = .continuousTranscription
    let channel = try WindowSpeechChannel(
      engine: engine, request: request, configuration: .init(continuousBoundaryMode: .adaptive))
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let packet = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    packet.frameLength = packet.frameCapacity
    for index in 0..<Int(packet.frameLength) { packet.floatChannelData?[0][index] = .nan }
    channel.append(packet)
    await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    channel.append(packet)
    let calls = await engine.count
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(failures.withLock { $0 }, 1)
    channel.cancel()
  }
}

extension WindowSpeechChannelTests {
  func testSharedModelKeepsSourceCalibrationIndependent() async throws {
    let model = WindowSpeechModel(
      engine: CountingWindowEngine(policy: .decode),
      configuration: .init(continuousBoundaryMode: .adaptive))
    let quietFinals = Mutex(0)
    var loudRequest = SpeechChannelRequest(
      language: .automatic, output: { _ in }, failure: { XCTFail($0) })
    loudRequest.context.purpose = .continuousTranscription
    var quietRequest = SpeechChannelRequest(
      language: .automatic, output: { if $0.isFinal { quietFinals.withLock { $0 += 1 } } },
      failure: { XCTFail($0) })
    quietRequest.context.purpose = .continuousTranscription
    let loud = try await model.makeChannel(loudRequest)
    let quiet = try await model.makeChannel(quietRequest)
    defer {
      loud.cancel()
      quiet.cancel()
    }
    for energy: Float in [0.03, 0, 0, 0, 0.0018, 0.0018, 0.0018] {
      let packet = try audioFrame(energy: energy)
      if energy == 0.03 { loud.append(packet) } else { quiet.append(packet) }
    }
    await withCheckedContinuation { continuation in quiet.finish { continuation.resume() } }
    XCTAssertGreaterThan(quietFinals.withLock { $0 }, 0)
  }

  func testWindowObserverCanCancelWithoutHoldingTheInputLock() async throws {
    let owner = Mutex<WindowSpeechChannel?>(nil)
    let observed = Mutex(0)
    let engine = CountingWindowEngine(policy: .decode)
    var request = SpeechChannelRequest(
      language: .automatic, output: { _ in XCTFail("Cancelled window produced text") },
      failure: { XCTFail($0) })
    request.measureWindow = { _ in
      observed.withLock { $0 += 1 }
      owner.withLock { $0 }?.cancel()
    }
    let channel = try WindowSpeechChannel(engine: engine, request: request)
    owner.withLock { $0 = channel }
    defer {
      owner.withLock { $0 = nil }
      channel.cancel()
    }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let packet = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    packet.frameLength = packet.frameCapacity
    for index in 0..<Int(packet.frameLength) { packet.floatChannelData?[0][index] = 0.1 }
    channel.append(packet)
    await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    let calls = await engine.count
    XCTAssertEqual(observed.withLock { $0 }, 1)
    XCTAssertEqual(calls, 0)
  }
}
