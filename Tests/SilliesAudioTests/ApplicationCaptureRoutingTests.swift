import CoreAudio
import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesAudio

private final class RoutingCapture: ApplicationCapture {
  enum Startup: Sendable { case success, unsupported, denied, broken, suspended }
  struct State {
    var startup = Startup.success
    var starts = 0
    var stops = 0
    var commands: [String] = []
    var continuation: CheckedContinuation<Void, any Error>?
    var stopFailure: SessionFailure?
    var duplicateStops = false
  }
  let state = Mutex(State())
  let receive: AudioCaptureInputQueue.Receiver
  let failure: ApplicationAudioRequest.Failure
  let started: @Sendable () -> Void
  init(
    receive: @escaping AudioCaptureInputQueue.Receiver,
    failure: @escaping ApplicationAudioRequest.Failure, started: @escaping @Sendable () -> Void = {}
  ) {
    self.receive = receive
    self.failure = failure
    self.started = started
  }
  func start() async throws {
    try await withCheckedThrowingContinuation { continuation in
      let startup = state.withLock { state in
        state.starts += 1
        if state.startup == .suspended { state.continuation = continuation }
        return state.startup
      }
      started()
      switch startup {
      case .success: continuation.resume()
      case .unsupported: continuation.resume(throwing: CoreAudioCaptureError.unsupported)
      case .denied:
        continuation.resume(
          throwing: SessionFailure.permissionDenied(.openSystemAudioRecordingSettings))
      case .broken:
        continuation.resume(
          throwing: CoreAudioCaptureError.native(.start, kAudioHardwareUnspecifiedError))
      case .suspended: break
      }
    }
  }
  func pause() { state.withLock { $0.commands.append("pause") } }
  func resume() { state.withLock { $0.commands.append("resume") } }
  func stop(completion: @escaping @Sendable (SessionFailure?) -> Void) {
    let result = state.withLock { state in
      state.stops += 1
      state.commands.append("stop")
      return (state.stopFailure, state.duplicateStops)
    }
    completion(result.0)
    if result.1 { completion(result.0) }
  }
  func releaseStart() {
    let continuation = state.withLock { state in
      let result = state.continuation
      state.continuation = nil
      return result
    }
    continuation?.resume()
  }
}

private final class RoutingFixture: Sendable {
  let preferred = Mutex<RoutingCapture?>(nil)
  let fallback = Mutex<RoutingCapture?>(nil)
  let failures = Mutex<[SessionFailure]>([])
  let packets = Mutex(0)
  let startup: RoutingCapture.Startup
  let cleanup: SessionFailure?
  init(_ startup: RoutingCapture.Startup, cleanup: SessionFailure? = nil) {
    self.startup = startup
    self.cleanup = cleanup
  }
  func make(started: @escaping @Sendable () -> Void = {}) -> ApplicationAudioSource {
    ApplicationAudioSource(
      providers: .init(
        preferred: { [self] receive, failure in
          let capture = RoutingCapture(receive: receive, failure: failure, started: started)
          capture.state.withLock {
            $0.startup = startup
            $0.stopFailure = cleanup
            $0.duplicateStops = true
          }
          preferred.withLock { $0 = capture }
          return capture
        },
        fallback: { [self] receive, failure in
          #expect(preferred.withLock { $0?.state.withLock { $0.stops } } == 1)
          let capture = RoutingCapture(receive: receive, failure: failure)
          fallback.withLock { $0 = capture }
          return capture
        }), receive: { [weak self] _ in self?.packets.withLock { $0 += 1 } },
      failure: { [weak self] event in self?.failures.withLock { $0.append(event) } })
  }
  func sendPacket(_ capture: RoutingCapture) throws {
    let emitter = try CoreAudioPacketEmitter(
      format: CoreAudioTestSystem.format,
      receive: capture.receive, failure: { _ in Issue.record("Unexpected packet failure") })
    coreAudioSend(emitter.receive)
  }
}

@Test func applicationCaptureFallsBackOnlyAfterUnsupportedProviderHasStopped() async throws {
  let fixture = RoutingFixture(.unsupported)
  let source = fixture.make()
  try await source.start()
  let preferred = try #require(fixture.preferred.withLock { $0 })
  let fallback = try #require(fixture.fallback.withLock { $0 })
  try fixture.sendPacket(preferred)
  try fixture.sendPacket(fallback)
  #expect(fixture.packets.withLock { $0 } == 1)
  preferred.failure(.permissionDenied(.openSystemAudioRecordingSettings))
  source.pause()
  source.resume()
  source.pause()
  source.resume()
  #expect(await coreAudioStop(source) == nil)
  #expect(
    fallback.state.withLock { $0.commands } == ["pause", "resume", "pause", "resume", "stop"])
  try fixture.sendPacket(fallback)
  #expect(fixture.packets.withLock { $0 } == 1)
  #expect(fixture.failures.withLock { $0.isEmpty })
}

@Test(arguments: [RoutingCapture.Startup.denied, .broken])
private func applicationCaptureDoesNotFallbackForPermissionOrArbitraryFailure(
  _ startup: RoutingCapture.Startup
) async {
  let fixture = RoutingFixture(startup)
  let source = fixture.make()
  do {
    try await source.start()
    Issue.record("Expected startup failure")
  } catch {}
  #expect(fixture.fallback.withLock { $0 } == nil)
  #expect(await coreAudioStop(source) == nil)
}

@Test func applicationCaptureCleanupFailurePreventsFallbackAndSurvivesDuplicateStops() async {
  let failure = SessionFailure(category: .finalization, message: "Fixture cleanup failure")
  let fixture = RoutingFixture(.unsupported, cleanup: failure)
  let source = fixture.make()
  do {
    try await source.start()
    Issue.record("Expected cleanup failure")
  } catch { #expect((error as? SessionFailure) == failure) }
  #expect(fixture.fallback.withLock { $0 } == nil)
  #expect(await coreAudioStop(source) == failure)
  #expect(await coreAudioStop(source) == failure)
}

@Test func applicationCaptureStopDuringStartupRejectsLatePacketsAndNeverStartsFallback()
  async throws
{
  let starts = AsyncStream<Void>.makeStream()
  let fixture = RoutingFixture(.suspended)
  let source = fixture.make { starts.continuation.yield(()) }
  let startup = Task { try await source.start() }
  var iterator = starts.stream.makeAsyncIterator()
  _ = await iterator.next()
  #expect(await coreAudioStop(source) == nil)
  let preferred = try #require(fixture.preferred.withLock { $0 })
  preferred.releaseStart()
  do {
    try await startup.value
    Issue.record("Stopped startup succeeded")
  } catch { #expect(error is CancellationError) }
  try fixture.sendPacket(preferred)
  #expect(fixture.packets.withLock { $0 } == 0)
  #expect(fixture.fallback.withLock { $0 } == nil)
  starts.continuation.finish()
}

@Test func applicationCaptureRuntimeFailureDoesNotSelectFallback() async throws {
  let updates = AsyncStream<SessionFailure>.makeStream()
  let active = Mutex<RoutingCapture?>(nil)
  let fallbackStarts = Mutex(0)
  let source = ApplicationAudioSource(
    providers: .init(
      preferred: { receive, failure in
        let capture = RoutingCapture(receive: receive, failure: failure)
        active.withLock { $0 = capture }
        return capture
      },
      fallback: { receive, failure in
        fallbackStarts.withLock { $0 += 1 }
        return RoutingCapture(receive: receive, failure: failure)
      }), receive: { _ in }, failure: { updates.continuation.yield($0) })
  try await source.start()
  let provider = try #require(active.withLock { $0 })
  let failure = SessionFailure(category: .captureInterrupted, message: "Fixture runtime error")
  provider.failure(failure)
  var iterator = updates.stream.makeAsyncIterator()
  #expect(await iterator.next() == failure)
  #expect(fallbackStarts.withLock { $0 } == 0)
  #expect(await coreAudioStop(source) == nil)
  updates.continuation.finish()
}

@Test func applicationCaptureCancellationStopsAnUncooperativeStartupAndRejectsLateSuccess()
  async throws
{
  let starts = AsyncStream<Void>.makeStream()
  let fixture = RoutingFixture(.suspended)
  let source = fixture.make { starts.continuation.yield(()) }
  let startup = Task { try await source.start() }
  var iterator = starts.stream.makeAsyncIterator()
  _ = await iterator.next()
  startup.cancel()
  #expect(await coreAudioStop(source) == nil)
  let preferred = try #require(fixture.preferred.withLock { $0 })
  preferred.releaseStart()
  do {
    try await startup.value
    Issue.record("Cancelled startup succeeded")
  } catch { #expect(error is CancellationError) }
  #expect(preferred.state.withLock { $0.stops } == 1)
  #expect(fixture.fallback.withLock { $0 } == nil)
  starts.continuation.finish()
}

@Test func applicationCapturePermissionRecoverySurvivesASeparateCleanupFailure() async {
  let cleanup = SessionFailure(category: .finalization, message: "Fixture cleanup failure")
  let fixture = RoutingFixture(.denied, cleanup: cleanup)
  let source = fixture.make()
  do {
    try await source.start()
    Issue.record("Expected permission failure")
  } catch {
    #expect((error as? SessionFailure)?.recovery == .openSystemAudioRecordingSettings)
  }
  #expect(await coreAudioStop(source) == cleanup)
  #expect(fixture.fallback.withLock { $0 } == nil)
}
