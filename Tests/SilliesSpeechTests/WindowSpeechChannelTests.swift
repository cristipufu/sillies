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
      var request = SpeechChannelRequest(
        language: .automatic,
        output: { phrase in
          phrases.withLock { $0.append(phrase) }
          if !phrase.isFinal { draft.fulfill() }
        }, failure: { message in XCTFail(message) })
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
      XCTAssertEqual(measurements.withLock { $0.count }, count)
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
  func testModelBoundaryRecommendationRespectsCapturePurposeAndExplicitOverride() async throws {
    let scenarios:
      [(
        SpeechRecognitionContext.Purpose, SpeechBoundaryPolicy.Mode, SpeechBoundaryPolicy.Mode?,
        Bool
      )] = [
        (.continuousTranscription, .baseline, nil, false),
        (.continuousTranscription, .adaptive, nil, true),
        (.continuousTranscription, .adaptive, .baseline, false),
        (.shortUtterance, .adaptive, nil, false),
      ]
    for (purpose, recommendation, override, shouldDecode) in scenarios {
      let engine = CountingWindowEngine(policy: .decode)
      let model = WindowSpeechModel(engine: engine, boundaryMode: recommendation)
      var request = SpeechChannelRequest(
        language: .automatic, output: { _ in }, failure: { XCTFail($0) })
      request.context.purpose = purpose
      request.context.boundaryMode = override
      let channel = try await model.makeChannel(request)
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
      let packet = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
      packet.frameLength = packet.frameCapacity
      for energy: Float in [0, 0, 0, 0.0018, 0.0018, 0.0018] {
        for index in 0..<Int(packet.frameLength) { packet.floatChannelData?[0][index] = energy }
        channel.append(packet)
      }
      await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
      let calls = await engine.count
      XCTAssertEqual(calls > 0, shouldDecode)
      channel.cancel()
    }
  }
}

extension WindowSpeechChannelTests {
  func testAdaptiveInvalidAudioReportsOnceAndStillCompletesFinalization() async throws {
    let failures = Mutex(0)
    let engine = CountingWindowEngine(policy: .decode)
    let channel = try WindowSpeechChannel(
      engine: engine,
      request: .init(
        language: .automatic, output: { _ in XCTFail("Invalid audio produced text") },
        failure: { _ in failures.withLock { $0 += 1 } }), boundaryMode: .adaptive)
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
