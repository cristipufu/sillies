import AVFoundation
import Foundation
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
