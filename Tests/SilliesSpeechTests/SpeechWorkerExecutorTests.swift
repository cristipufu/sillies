import Foundation
import XCTest

@testable import SilliesSpeech

final class SpeechWorkerExecutorTests: XCTestCase, @unchecked Sendable {
  @MainActor func testReleasingTheLastUIReferenceDestroysModelOnWorker() async {
    let released = expectation(description: "Released model off the UI queue")
    var model: OwnedModel? = OwnedModel {
      XCTAssertFalse(Thread.isMainThread)
      released.fulfill()
    }
    let runsOnMain = await model?.isMainThread()
    XCTAssertEqual(runsOnMain, false)
    model = nil
    await fulfillment(of: [released], timeout: 2)
  }
}

private actor OwnedModel {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private let released: @Sendable () -> Void
  init(released: @escaping @Sendable () -> Void) { self.released = released }
  func isMainThread() -> Bool { Thread.isMainThread }
  isolated deinit { released() }
}
