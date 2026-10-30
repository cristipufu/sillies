import AVFoundation
import Foundation
import Synchronization
import XCTest

@testable import SilliesSpeech

final class StreamingDiarizationTests: XCTestCase, @unchecked Sendable {
  func testFinishDrainsOnWorkerAndCancelRejectsLateAudio() async throws {
    let engine = CountingSpeakerEngine()
    let outputs = Mutex(0)
    let channel = try StreamingDiarizationChannel(
      engine: engine,
      request: .init(output: { _ in outputs.withLock { $0 += 1 } }, failure: { XCTFail($0) }))
    let buffer = try buffer(seconds: 2)
    channel.append(buffer)
    await withCheckedContinuation { continuation in
      channel.finish { continuation.resume() }
    }
    let count = await engine.samples
    let offMain = await engine.offMain
    XCTAssertEqual(count, 32_000)
    XCTAssertTrue(offMain)
    XCTAssertEqual(outputs.withLock { $0 }, 1)
    channel.append(buffer)
    channel.cancel()
    let finalCount = await engine.samples
    XCTAssertEqual(finalCount, count)
  }

  func testOverloadReportsOnceAndAllowsReentrantCancellation() throws {
    let owner = Mutex<StreamingDiarizationChannel?>(nil)
    let failures = Mutex(0)
    let channel = try StreamingDiarizationChannel(
      engine: CountingSpeakerEngine(),
      request: .init(
        output: { _ in },
        failure: { _ in
          failures.withLock { $0 += 1 }
          owner.withLock { $0 }?.cancel()
        }))
    owner.withLock { $0 = channel }
    defer { owner.withLock { $0 = nil } }
    let oversized = try buffer(seconds: 17)
    channel.append(oversized)
    channel.append(oversized)
    XCTAssertEqual(failures.withLock { $0 }, 1)
    let finished = Mutex(false)
    channel.finish { finished.withLock { $0 = true } }
    XCTAssertTrue(finished.withLock { $0 })
  }

  private func buffer(seconds: Int) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 16_000)))
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
    return buffer
  }
}

private actor CountingSpeakerEngine: SpeakerDiarizationEngine {
  private(set) var samples = 0
  private(set) var offMain = true
  func append(_ input: [Float]) async throws -> [SpeakerActivityBatch] {
    samples += input.count
    offMain = offMain && !Thread.isMainThread
    return []
  }
  func finish() async throws -> [SpeakerActivityBatch] {
    [.init(start: 0, frameDuration: 1, speakerCount: 1, probabilities: [0.9, 0.9])]
  }
}
