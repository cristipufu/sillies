import AVFoundation
import Foundation
import SilliesInference
import Synchronization
import XCTest

@testable import SilliesSpeech

final class InteractiveSpeechChannelTests: XCTestCase, @unchecked Sendable {
  func testFinalizationWaitsForReservationRelease() async throws {
    try await assertReleaseBeforeCompletion(.finish)
  }

  func testFinalizationJoinsReleaseAlreadyStartedByCancellation() async throws {
    try await assertReleaseBeforeCompletion(.cancelThenFinish)
  }

  func testFailedPreparationReleasesReservationBeforeReturning() async {
    let activity = InferenceActivity()
    do {
      _ = try await InteractiveSpeechChannel.make(activity: activity) {
        throw SpeechError.unavailable("Fixture preparation failure")
      }
      XCTFail("Preparation should fail")
    } catch is SpeechError {} catch { XCTFail("Unexpected error: \(error)") }
    let speech = UUID()
    let admitted = await activity.claimSynthesis(speech, cancel: {})
    XCTAssertTrue(admitted)
    await activity.releaseSynthesis(speech)
  }

  private enum FinishOrder { case finish, cancelThenFinish }

  private func assertReleaseBeforeCompletion(_ order: FinishOrder) async throws {
    let activity = InferenceActivity()
    await activity.beginSpeech()
    let gate = ReservationReleaseGate()
    let releaseStarted = expectation(description: "Release started")
    let finished = expectation(description: "Finalization completed")
    let releaseCount = Mutex(0)
    let didFinish = Mutex(false)
    let reservation = SpeechReservation {
      releaseCount.withLock { $0 += 1 }
      releaseStarted.fulfill()
      await gate.wait()
      await activity.endSpeech()
    }
    let channel = InteractiveSpeechChannel(base: ImmediateSpeechChannel(), reservation: reservation)
    if order == .cancelThenFinish { channel.cancel() }
    channel.finish {
      didFinish.withLock { $0 = true }
      finished.fulfill()
    }
    await fulfillment(of: [releaseStarted], timeout: 2)
    XCTAssertFalse(didFinish.withLock { $0 }, "Finalization must not overtake a pending release")
    await gate.open()
    await fulfillment(of: [finished], timeout: 2)
    let speech = UUID()
    let admitted = await activity.claimSynthesis(speech, cancel: {})
    XCTAssertTrue(admitted, "The completion must permit immediate synthesis")
    await activity.releaseSynthesis(speech)

    // A late cancellation must not release a newer recognition turn's reservation.
    await activity.beginSpeech()
    channel.cancel()
    await reservation.release().value
    let admittedDuringRecognition = await activity.claimSynthesis(UUID(), cancel: {})
    XCTAssertFalse(admittedDuringRecognition)
    XCTAssertEqual(releaseCount.withLock { $0 }, 1)
    await activity.endSpeech()
  }
}

private final class ImmediateSpeechChannel: LocalSpeechChannel {
  func append(_ buffer: AVAudioPCMBuffer) {}
  func finish(completion: @escaping @Sendable () -> Void) { completion() }
  func cancel() {}
}

private actor ReservationReleaseGate {
  private var isOpen = false
  private var waiter: CheckedContinuation<Void, Never>?

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiter = $0 }
  }

  func open() {
    isOpen = true
    waiter?.resume()
    waiter = nil
  }
}
