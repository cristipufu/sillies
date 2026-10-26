import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

private actor WindowRegionsProbe {
  private(set) var calls = 0
  private var waiting: [CheckedContinuation<[DragWindowRegion], Never>] = []

  func load() async -> [DragWindowRegion] {
    calls += 1
    return await withCheckedContinuation { waiting.append($0) }
  }

  func finish(_ regions: [DragWindowRegion]) {
    guard !waiting.isEmpty else { return }
    waiting.removeFirst().resume(returning: regions)
  }
}

@Test @MainActor func windowStackHitTestingUsesCachedRectanglesWithoutRepeatedDiscovery()
  async throws
{
  let probe = WindowRegionsProbe()
  let snapshot = DragWindowSnapshot(load: { _ in await probe.load() })
  snapshot.start(seed: nil)
  defer { snapshot.stop() }
  try await waitForWindowRegions { await probe.calls == 1 }
  await probe.finish([
    DragWindowRegion(windowID: 2, frame: CGRect(x: 100, y: 100, width: 200, height: 200)),
    DragWindowRegion(windowID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
  ])
  try await waitForWindowRegions { snapshot.hitTest(at: CGPoint(x: 150, y: 150), below: 0) == 2 }
  for _ in 0..<1000 {
    #expect(snapshot.hitTest(at: CGPoint(x: 150, y: 150), below: 0) == 2)
    #expect(snapshot.hitTest(at: CGPoint(x: 150, y: 150), below: 2) == 1)
    #expect(snapshot.hitTest(at: CGPoint(x: 400, y: 400), below: 0) == 1)
  }
  #expect(await probe.calls == 1)
}

@Test @MainActor func windowStackDiscoveryStopsAndCannotReappearAfterPause() async throws {
  let probe = WindowRegionsProbe()
  let snapshot = DragWindowSnapshot(load: { _ in await probe.load() })
  snapshot.start(seed: nil)
  try await waitForWindowRegions { await probe.calls == 1 }
  snapshot.stop()
  await probe.finish([
    DragWindowRegion(windowID: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500))
  ])
  try await Task.sleep(for: .milliseconds(5))
  #expect(snapshot.hitTest(at: CGPoint(x: 100, y: 100), below: 0) == 0)
  snapshot.refresh()
  #expect(await probe.calls == 1)
}

@Test @MainActor func targetedGeometryRemainsNewerThanAnInFlightStackSnapshot() async throws {
  let probe = WindowRegionsProbe()
  let snapshot = DragWindowSnapshot(load: { _ in await probe.load() })
  let original = CGRect(x: 0, y: 0, width: 100, height: 100)
  let moved = CGRect(x: 200, y: 0, width: 100, height: 100)
  var changes = 0
  snapshot.onChange = { changes += 1 }
  snapshot.start(
    seed: WindowTargetCandidate(windowID: 1, processID: 1, appName: "Test", frame: original))
  defer { snapshot.stop() }
  try await waitForWindowRegions { await probe.calls == 1 }
  snapshot.updateKnownWindow(1, frame: moved)
  await probe.finish([DragWindowRegion(windowID: 1, frame: original)])
  try await waitForWindowRegions { changes >= 2 }
  #expect(snapshot.hitTest(at: CGPoint(x: 250, y: 50), below: 0) == 1)
  #expect(snapshot.hitTest(at: CGPoint(x: 50, y: 50), below: 0) == 0)
}

@Test @MainActor func rapidWindowStackInvalidationsCoalesceToOneFollowup() async throws {
  let probe = WindowRegionsProbe()
  let snapshot = DragWindowSnapshot(load: { _ in await probe.load() })
  snapshot.start(seed: nil)
  defer { snapshot.stop() }
  try await waitForWindowRegions { await probe.calls == 1 }
  for _ in 0..<100 { snapshot.refresh() }
  await probe.finish([])
  try await waitForWindowRegions { await probe.calls == 2 }
  await probe.finish([])
  try await Task.sleep(for: .milliseconds(5))
  #expect(await probe.calls == 2)
}

@MainActor
private func waitForWindowRegions(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(1))
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  let satisfied = await condition()
  #expect(satisfied, "Timed out waiting for window-stack metadata")
}
