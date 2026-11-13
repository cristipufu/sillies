import CoreAudio
import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesAudio

@Test func coreAudioCaptureOwnsPauseResumeDeviceChangesAndStaleCallbacks() async throws {
  let system = CoreAudioTestSystem()
  let packets = Mutex(0)
  let (events, continuation) = AsyncStream<CoreAudioTestSystem.Step>.makeStream()
  system.state.withLock { state in
    for step in [CoreAudioTestSystem.Step.start, .destroyTap] {
      state.hooks[step] = { continuation.yield(step) }
    }
  }
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in packets.withLock { $0 += 1 } },
      failure: { _ in Issue.record("Unexpected capture failure") }),
    identity: { _ in .verified }, makeSystem: { system })
  defer {
    system.state.withLock { $0.oldReceivers.removeAll() }
    continuation.finish()
  }
  var iterator = events.makeAsyncIterator()
  try await capture.start()
  #expect(await iterator.next() == .start)
  let original = try #require(system.state.withLock { $0.receive })
  coreAudioSend(original)
  capture.pause()
  #expect(await iterator.next() == .destroyTap)
  coreAudioSend(original)
  #expect(packets.withLock { $0 } == 1)
  capture.resume()
  #expect(await iterator.next() == .start)
  system.state.withLock {
    $0.selection = .init(
      processes: [21], output: .init(id: 32, uid: "new-output", sampleRate: 44_100))
  }
  system.change(.configuration)
  #expect(await iterator.next() == .destroyTap)
  #expect(await iterator.next() == .start)
  let current = try #require(system.state.withLock { $0.receive })
  coreAudioSend(original)
  coreAudioSend(current)
  #expect(packets.withLock { $0 } == 2)
  #expect(await coreAudioStop(capture) == nil)
  coreAudioSend(current)
  capture.resume()
  #expect(await coreAudioStop(capture) == nil)
  #expect(system.state.withLock { $0.steps.filter { $0 == .start }.count } == 3)
}

@Test(arguments: [ApplicationAudioIdentity.ambiguous, .unavailable])
func coreAudioRuntimeScopeFailureStopsInsteadOfFallingBack(
  _ changedIdentity: ApplicationAudioIdentity
) async throws {
  let system = CoreAudioTestSystem()
  let verified = Mutex(true)
  let (events, continuation) = AsyncStream<SessionFailure>.makeStream()
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in }, failure: { continuation.yield($0) }),
    identity: { _ in verified.withLock { $0 } ? .verified : changedIdentity },
    makeSystem: { system })
  defer {
    system.state.withLock { $0.oldReceivers.removeAll() }
    continuation.finish()
  }
  try await capture.start()
  verified.withLock { $0 = false }
  system.change(.processes)
  var iterator = events.makeAsyncIterator()
  let failure = try #require(await iterator.next())
  #expect(failure.category == .captureInterrupted)
  #expect(!failure.requiresAttention(ending: .sourceClosed))
  #expect(await coreAudioStop(capture) == nil)
  #expect(system.state.withLock { $0.steps.filter { $0 == .start }.count } == 1)
}

@Test func coreAudioStopDuringStartupWaitsForNativeResourcesAndSuppressesPackets() async throws {
  let system = CoreAudioTestSystem()
  let entered = AsyncStream<Void>.makeStream()
  let gate = DispatchSemaphore(value: 0)
  system.state.withLock {
    $0.hooks[.start] = {
      entered.continuation.yield(())
      gate.wait()
    }
  }
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in Issue.record("Stopped startup emitted audio") }, failure: { _ in }),
    identity: { _ in .verified }, makeSystem: { system })
  defer {
    system.state.withLock { $0.oldReceivers.removeAll() }
    entered.continuation.finish()
  }
  let startup = Task { try await capture.start() }
  var starts = entered.stream.makeAsyncIterator()
  _ = await starts.next()
  let finished = Mutex(false)
  let stopped = AsyncStream<Void>.makeStream()
  capture.stop { _ in
    finished.withLock { $0 = true }
    stopped.continuation.yield(())
  }
  #expect(!finished.withLock { $0 })
  coreAudioSend(try #require(system.state.withLock { $0.receive }))
  gate.signal()
  do {
    try await startup.value
    Issue.record("Cancelled startup succeeded")
  } catch { #expect(error is CancellationError) }
  var stops = stopped.stream.makeAsyncIterator()
  _ = await stops.next()
  stopped.continuation.finish()
  #expect(
    system.state.withLock { $0.steps.contains(.destroyProcessor) && $0.steps.contains(.destroyTap) }
  )
}

@Test func coreAudioStartupCancellationReleasesEveryNativeHandle() async throws {
  let system = CoreAudioTestSystem()
  let entered = AsyncStream<Void>.makeStream()
  let gate = DispatchSemaphore(value: 0)
  system.state.withLock {
    $0.hooks[.device] = {
      entered.continuation.yield(())
      gate.wait()
    }
  }
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in }, failure: { _ in }), identity: { _ in .verified }, makeSystem: { system })
  defer {
    system.state.withLock { $0.oldReceivers.removeAll() }
    entered.continuation.finish()
  }
  let startup = Task { try await capture.start() }
  var iterator = entered.stream.makeAsyncIterator()
  _ = await iterator.next()
  startup.cancel()
  gate.signal()
  do {
    try await startup.value
    Issue.record("Cancelled startup succeeded")
  } catch { #expect(error is CancellationError) }
  #expect(await coreAudioStop(capture) == nil)
  #expect(
    system.state.withLock { $0.steps.contains(.destroyDevice) && $0.steps.contains(.destroyTap) })
}

@Test func coreAudioRepeatedStartupCannotTearDownTheActiveCapture() async throws {
  let system = CoreAudioTestSystem()
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in }, failure: { _ in Issue.record("Unexpected capture failure") }),
    identity: { _ in .verified }, makeSystem: { system })
  defer { system.state.withLock { $0.oldReceivers.removeAll() } }
  try await capture.start()
  do {
    try await capture.start()
    Issue.record("Repeated startup was accepted")
  } catch { #expect(error is CancellationError) }
  #expect(!system.state.withLock { $0.steps.contains(.stop) })
  #expect(await coreAudioStop(capture) == nil)
}

@Test func coreAudioChangeBurstKeepsTheNewestTicketAndConfigurationChange() async throws {
  let queue = DispatchQueue(label: "sillies.test.native-changes")
  let gate = DispatchSemaphore(value: 0)
  queue.async { gate.wait() }
  let received = Mutex<[CoreAudioChangeDelivery.Signal]>([])
  let changes = CoreAudioChangeDelivery(queue: queue) { signal in
    received.withLock { $0.append(signal) }
  }
  changes.send(.init(change: .configuration, ticket: UUID()))
  for _ in 0..<1_000 { changes.send(.init(change: .processes, ticket: UUID())) }
  let newest = UUID()
  changes.send(.init(change: .processes, ticket: newest))
  gate.signal()
  await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  let signals = received.withLock { $0 }
  #expect(signals.count == 1)
  #expect(signals.first?.ticket == newest && signals.first?.change == .configuration)
}

@Test func coreAudioInvalidNativeSelectionsRejectBeforeCreatingAnyTap() {
  let system = NativeCoreAudioTapSystem()
  for processes in [
    [], [kAudioObjectUnknown],
    Array(repeating: 1, count: CoreAudioProperties.maximumObjects + 1),
  ] {
    do {
      _ = try system.createTap(processes: processes)
      Issue.record("Invalid selection was accepted")
    } catch {
      guard case CoreAudioCaptureError.unsupported = error else {
        Issue.record("Unexpected error")
        continue
      }
    }
  }
}

@Test func coreAudioFailedPauseCannotOverwriteResourcesOnResume() async throws {
  let system = CoreAudioTestSystem()
  let updates = AsyncStream<SessionFailure>.makeStream()
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in }, failure: { updates.continuation.yield($0) }),
    identity: { _ in .verified }, makeSystem: { system })
  defer {
    system.state.withLock { $0.oldReceivers.removeAll() }
    updates.continuation.finish()
  }
  try await capture.start()
  system.state.withLock { $0.failures[.stop] = 2 }
  capture.pause()
  var iterator = updates.stream.makeAsyncIterator()
  #expect(await iterator.next()?.category == .captureInterrupted)
  capture.resume()
  #expect(await coreAudioStop(capture) == nil)
  #expect(system.state.withLock { $0.steps.filter { $0 == .tap }.count } == 1)
}

@Test func coreAudioPermissionRecoverySurvivesASeparateCleanupFailure() async {
  let system = CoreAudioTestSystem()
  system.state.withLock {
    $0.failures[.start] = 1
    $0.statuses[.start] = kAudioDevicePermissionsError
    $0.failures[.stop] = 2
  }
  let capture = CoreAudioApplicationCapture(
    request: .init(
      target: CoreAudioTestSystem.target,
      receive: { _ in }, failure: { _ in }), identity: { _ in .verified }, makeSystem: { system })
  defer { system.state.withLock { $0.oldReceivers.removeAll() } }
  do {
    try await capture.start()
    Issue.record("Expected permission failure")
  } catch { #expect((error as? SessionFailure)?.recovery == .openSystemAudioRecordingSettings) }
  #expect(await coreAudioStop(capture) == nil)
  #expect(system.state.withLock { $0.steps.contains(.destroyTap) })
}
