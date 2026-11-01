import Foundation
import XCTest

@testable import SilliesSpeech

final class SpeechEnginePoolTests: XCTestCase, @unchecked Sendable {
  func testCompletedTurnsReuseResetEngineAndKeepLanguagesSeparate() async throws {
    let initial = PoolEngine()
    let created = PoolFactory()
    let pool = SpeechEnginePool(prepared: ("auto", initial), make: { await created.make($0) })
    let first = try await pool.acquire(for: "auto")
    let one = try await first.transcribe(request)
    XCTAssertEqual(one.words.first?.text, "1")
    await first.release()
    let second = try await pool.acquire(for: "auto")
    let two = try await second.transcribe(request)
    XCTAssertEqual(two.words.first?.text, "1", "Decoder history must be empty on reuse")
    await second.release()
    let language = try await pool.acquire(for: "fr")
    await language.release()
    let calls = await created.calls
    let resets = await initial.resets
    XCTAssertEqual(calls, ["fr"])
    XCTAssertEqual(resets, 2)
  }

  func testSimultaneousSourcesNeverLeaseTheSameEngine() async throws {
    let created = PoolFactory()
    let pool = SpeechEnginePool(prepared: ("auto", PoolEngine()), make: { await created.make($0) })
    let first = try await pool.acquire(for: "auto")
    let second = try await pool.acquire(for: "auto")
    let firstResult = try await first.transcribe(request)
    let secondResult = try await second.transcribe(request)
    XCTAssertEqual(firstResult.words.first?.text, "1")
    XCTAssertEqual(secondResult.words.first?.text, "1")
    let calls = await created.calls
    XCTAssertEqual(calls.count, 1)
    await first.release()
    await second.release()
  }

  func testCancellationWaitsForNativeCallBeforeResetAndReuse() async throws {
    let engine = PoolEngine()
    await engine.holdInference()
    let created = PoolFactory()
    let pool = SpeechEnginePool(prepared: ("auto", engine), make: { await created.make($0) })
    let lease = try await pool.acquire(for: "auto")
    let work = Task { try await lease.transcribe(request) }
    await engine.waitUntilStarted()
    let release = Task { await lease.release() }
    work.cancel()
    let next = try await pool.acquire(for: "auto")
    let resetsBeforeReturn = await engine.resets
    XCTAssertEqual(resetsBeforeReturn, 0)
    await engine.completeInference()
    _ = await work.result
    await release.value
    let resetsAfterReturn = await engine.resets
    XCTAssertEqual(resetsAfterReturn, 1)
    do {
      _ = try await lease.transcribe(request)
      XCTFail("Released lease accepted work")
    } catch is CancellationError {}
    await next.release()
  }

  func testFailedEngineIsDiscardedAndReleaseIsIdempotent() async throws {
    let engine = PoolEngine()
    await engine.failInference()
    let created = PoolFactory()
    let pool = SpeechEnginePool(prepared: ("auto", engine), make: { await created.make($0) })
    let lease = try await pool.acquire(for: "auto")
    do {
      _ = try await lease.transcribe(request)
      XCTFail("Failure expected")
    } catch {}
    await lease.release()
    await lease.release()
    let replacement = try await pool.acquire(for: "auto")
    let calls = await created.calls
    XCTAssertEqual(calls.count, 1)
    await replacement.release()
  }

  func testIdlePoolIsBounded() async throws {
    let created = PoolFactory()
    let pool = SpeechEnginePool(prepared: ("auto", PoolEngine()), make: { await created.make($0) })
    for key in ["a", "b", "c", "a"] {
      let lease = try await pool.acquire(for: key)
      await lease.release()
    }
    let calls = await created.calls
    XCTAssertEqual(calls, ["a", "b", "c", "a"])
  }

  func testSpeechPriorityMatchesInteractiveIntent() {
    XCTAssertEqual(SpeechRecognitionContext.Priority.interactive.taskPriority, .userInitiated)
    XCTAssertEqual(SpeechRecognitionContext.Priority.live.taskPriority, .utility)
  }

  private var request: SpeechWindowRequest { .init(samples: [1], language: .automatic) }
}

private actor PoolFactory {
  private(set) var calls: [String] = []
  func make(_ key: String) -> any ReusableSpeechEngine {
    calls.append(key)
    return PoolEngine()
  }
}

private actor PoolEngine: ReusableSpeechEngine {
  private var count = 0
  private(set) var resets = 0
  private var holding = false
  private var failing = false
  private var started = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  private var completion: CheckedContinuation<Void, Never>?
  func holdInference() { holding = true }
  func failInference() { failing = true }
  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiter = $0 }
  }
  func completeInference() {
    completion?.resume()
    completion = nil
  }
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    started = true
    startWaiter?.resume()
    startWaiter = nil
    if holding { await withCheckedContinuation { completion = $0 } }
    if failing { throw SpeechError.overloaded }
    count += 1
    return .init(words: [.init(text: String(count), start: 0, end: 1)])
  }
  func resetForReuse() {
    resets += 1
    count = 0
  }
}
