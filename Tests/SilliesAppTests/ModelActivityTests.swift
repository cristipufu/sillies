import Foundation
import Testing

@testable import SilliesApp

@Test @MainActor func modelActivityWakeWaitsForSuspensionAndCoalescesRapidChanges() async throws {
  let probe = HeldModelActivity()
  let coordinator = ModelActivityCoordinator(apply: probe.apply)
  coordinator.setActivity(.active)
  try await waitForModelActivity { probe.finished == [.active] }
  probe.hold = .suspended
  coordinator.setActivity(.suspended)
  try await waitForModelActivity { probe.isWaiting }
  for _ in 0..<1_000 {
    coordinator.setActivity(.active)
    coordinator.setActivity(.suspended)
  }
  coordinator.setActivity(.active)
  #expect(probe.started == [.active, .suspended])
  probe.release()
  try await waitForModelActivity { probe.finished == [.active, .suspended, .active] }
  #expect(probe.maximumConcurrent == 1)
  coordinator.stop()
  try await waitForModelActivity { probe.finished.last == .suspended }
}

@Test @MainActor func modelActivityStopDrainsAnInFlightWakeBeforeFinalSuspension() async throws {
  let probe = HeldModelActivity()
  probe.hold = .active
  let coordinator = ModelActivityCoordinator(apply: probe.apply)
  coordinator.setActivity(.active)
  try await waitForModelActivity { probe.isWaiting }
  coordinator.stop()
  probe.release()
  try await waitForModelActivity { probe.finished == [.active, .suspended] }
  #expect(probe.maximumConcurrent == 1)
  // A cancelled quit can resume the same owner once its pending teardown has finished.
  coordinator.setActivity(.active)
  try await waitForModelActivity { probe.finished == [.active, .suspended, .active] }
  coordinator.stop()
  try await waitForModelActivity { probe.finished.last == .suspended }
}

@MainActor private final class HeldModelActivity {
  typealias Activity = ModelActivityCoordinator.Activity
  var hold: Activity?
  private var continuation: CheckedContinuation<Void, Never>?
  private var concurrent = 0
  private(set) var maximumConcurrent = 0
  private(set) var started: [Activity] = []
  private(set) var finished: [Activity] = []
  var isWaiting: Bool { continuation != nil }

  func apply(_ activity: Activity) async {
    concurrent += 1
    maximumConcurrent = max(maximumConcurrent, concurrent)
    started.append(activity)
    if activity == hold {
      hold = nil
      await withCheckedContinuation { continuation = $0 }
    }
    finished.append(activity)
    concurrent -= 1
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor private func waitForModelActivity(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(condition())
}
