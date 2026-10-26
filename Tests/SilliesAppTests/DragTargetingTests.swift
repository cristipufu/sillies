import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

private actor TargetLookupProbe {
  private(set) var calls: [UInt32] = []
  private var waiting: [UInt32: CheckedContinuation<WindowTargetCandidate?, Never>] = [:]

  func read(_ id: UInt32) async -> WindowTargetCandidate? {
    calls.append(id)
    return await withCheckedContinuation { waiting[id] = $0 }
  }

  func finish(_ id: UInt32, target: WindowTargetCandidate?) {
    waiting.removeValue(forKey: id)?.resume(returning: target)
  }
}

@MainActor
private final class WindowHitTestProbe {
  var frontmost = 1
  var hits = 0
  func hit(_ point: CGPoint, below: Int) -> Int {
    hits += 1
    return below == 0 ? frontmost : 0
  }
}

@Test @MainActor func slowTargetMetadataLeavesTheMainActorResponsiveAndCoalescesMovement()
  async throws
{
  let probe = TargetLookupProbe()
  let windows = WindowHitTestProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { windows.hit($0, below: $1) },
    lookup: { id, _ in await probe.read(id) })
  var published: [UInt32] = []
  resolver.onTargetChanged = { if let id = $0?.windowID { published.append(id) } }
  resolver.start()
  defer { resolver.stop() }
  resolver.update(at: CGPoint(x: 100, y: 100), excluding: [])
  try await eventually { await probe.calls == [1] }
  for _ in 0..<100 { resolver.update(at: CGPoint(x: 110, y: 100), excluding: []) }
  windows.frontmost = 2
  resolver.update(at: CGPoint(x: 120, y: 100), excluding: [])
  windows.frontmost = 3
  resolver.update(at: CGPoint(x: 130, y: 100), excluding: [])
  var heartbeat = false
  Task { @MainActor in heartbeat = true }
  try await eventually { heartbeat }
  #expect(await probe.calls == [1])
  await probe.finish(1, target: dragTestTarget(1))
  try await eventually { await probe.calls == [1, 3] }
  #expect(published.isEmpty)
  await probe.finish(3, target: dragTestTarget(3))
  try await eventually { resolver.currentTarget?.windowID == 3 }
  #expect(published == [3])
  for _ in 0..<100 { resolver.update(at: CGPoint(x: 140, y: 100), excluding: []) }
  #expect(await probe.calls == [1, 3])
}

@Test @MainActor func stoppingTargetingDiscardsLateRepliesFromThePreviousDrag() async throws {
  let probe = TargetLookupProbe()
  let windows = WindowHitTestProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { windows.hit($0, below: $1) },
    lookup: { id, _ in await probe.read(id) })
  resolver.start()
  resolver.update(at: CGPoint(x: 100, y: 100), excluding: [])
  try await eventually { await probe.calls == [1] }
  resolver.stop()
  resolver.start()
  windows.frontmost = 2
  resolver.update(at: CGPoint(x: 100, y: 100), excluding: [])
  try await eventually { await probe.calls == [1, 2] }
  await probe.finish(1, target: dragTestTarget(1))
  #expect(resolver.currentTarget == nil)
  await probe.finish(2, target: dragTestTarget(2))
  try await eventually { resolver.currentTarget?.windowID == 2 }
  resolver.stop()
  #expect(resolver.currentTarget == nil)
}

@Test @MainActor func targetingSkipsOurOverlaysAndNonDocumentWindows() async throws {
  let probe = TargetLookupProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { _, below in
      switch below {
      case 0: 8
      case 8: 99
      case 99: 7
      default: 0
      }
    },
    lookup: { id, _ in await probe.read(id) })
  resolver.start()
  defer { resolver.stop() }
  let point = CGPoint(x: 100, y: 100)
  resolver.update(at: point, excluding: [8])
  try await eventually { await probe.calls == [99] }
  await probe.finish(99, target: nil)
  try await eventually { await probe.calls == [99, 7] }
  await probe.finish(7, target: dragTestTarget(7))
  try await eventually { resolver.currentTarget?.windowID == 7 }
  #expect(resolver.cachedTarget(at: point, excluding: [8])?.windowID == 7)
}

@Test @MainActor func quickDropsResolveWithoutAnActiveHoverSession() async throws {
  let probe = TargetLookupProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { _, below in below == 0 ? 9 : 0 },
    lookup: { id, _ in await probe.read(id) })
  let request = try #require(resolver.dropTarget(at: CGPoint(x: 100, y: 100), excluding: []))
  let task = Task { await resolver.resolveDrop(request) }
  try await eventually { await probe.calls == [9] }
  await probe.finish(9, target: dragTestTarget(9))
  #expect(await task.value?.windowID == 9)
}

@Test @MainActor func actualMetadataWorkerNeverBlocksTheMainThread() async throws {
  let (started, signal) = AsyncStream<Void>.makeStream()
  let gate = DispatchSemaphore(value: 0)
  defer {
    gate.signal()
    signal.finish()
  }
  let worker = WindowTargetMetadata { id, _ in
    #expect(!Thread.isMainThread)
    signal.yield()
    gate.wait()
    return dragTestTarget(id)
  }
  var finished = false
  let task = Task {
    let result = await worker.candidate(for: 1, primaryScreenTop: 1000)
    finished = true
    return result
  }
  for await _ in started { break }
  var heartbeat = false
  Task { @MainActor in heartbeat = true }
  try await eventually { heartbeat }
  #expect(!finished)
  gate.signal()
  #expect(await task.value?.windowID == 1)
}

@Test @MainActor func dragOverlaysArePreparedHiddenAndReusedAcrossGestures() throws {
  let highlight = WindowDropHighlightController()
  let wheel = RadialWheelController()
  defer {
    highlight.close()
    wheel.close()
  }
  highlight.prepare()
  wheel.prepare()
  let highlightID = try #require(highlight.windowNumber)
  let wheelID = try #require(wheel.windowNumber)
  #expect(highlightID > 0 && wheelID > 0)
  #expect(NSApp.windows.first(where: { $0.windowNumber == highlightID })?.isVisible == false)
  #expect(NSApp.windows.first(where: { $0.windowNumber == wheelID })?.isVisible == false)
  #expect(
    NSApp.windows.first(where: { $0.windowNumber == highlightID })?.animationBehavior
      == NSWindow.AnimationBehavior.none)
  #expect(
    NSApp.windows.first(where: { $0.windowNumber == wheelID })?.animationBehavior
      == NSWindow.AnimationBehavior.none)
  highlight.prepare()
  wheel.prepare()
  #expect(highlight.windowNumber == highlightID && wheel.windowNumber == wheelID)
}

private func dragTestTarget(_ id: UInt32) -> WindowTargetCandidate {
  WindowTargetCandidate(
    windowID: id, processID: Int32(id), appName: "Test \(id)",
    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
}

@MainActor
private func eventually(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(1))
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  let satisfied = await condition()
  #expect(satisfied, "Timed out waiting for asynchronous targeting")
}

@Test @MainActor func quickDropKeepsTheWindowFromMouseUpEvenIfAnotherWindowMovesUnderIt()
  async throws
{
  let probe = TargetLookupProbe()
  let windows = WindowHitTestProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { windows.hit($0, below: $1) }, lookup: { id, _ in await probe.read(id) })
  let request = try #require(resolver.dropTarget(at: CGPoint(x: 100, y: 100), excluding: []))
  windows.frontmost = 2
  let task = Task { await resolver.resolveDrop(request) }
  try await eventually { await probe.calls == [1] }
  await probe.finish(1, target: dragTestTarget(1))
  #expect(await task.value?.windowID == 1)
}

@Test @MainActor func tinyPointerUpdatesDoNotFloodWindowServerWithHitTests() {
  let windows = WindowHitTestProbe()
  let resolver = DragWindowTargetResolver(
    hitTest: { windows.hit($0, below: $1) }, lookup: { _, _ in nil })
  resolver.start()
  for index in 0..<100 {
    resolver.update(at: CGPoint(x: 100 + Double(index % 3), y: 100), excluding: [])
  }
  #expect(windows.hits < 10)
  resolver.stop()
}

@Test @MainActor
func dropTargetingValidatesLiveWindowOrderWhenOverlappingWindowsReorderDuringDrag() async throws {
  let snapshot = DragWindowSnapshot(load: { _ in
    [
      DragWindowRegion(windowID: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
      DragWindowRegion(windowID: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
    ]
  })
  // Live window stack reordered so window 2 is now above window 1 at release time.
  let controller = CompanionDragTargetingController(
    metrics: DragResponseMetrics(enabled: false),
    snapshot: snapshot,
    dropHitTest: { _, below in below == 0 ? 2 : 0 },
    lookup: { id, _ in dragTestTarget(id) })
  controller.start()
  defer { controller.stop() }

  let pet = CompanionInstance(
    definition: try CharacterCatalog().characters[0],
    rig: CatRig(),
    size: 64,
    seed: 1,
    transitions: TransitionLibrary())
  defer {
    pet.hud.close()
    pet.presentation.close()
  }
  pet.isPickedUp = true
  controller.beginDrag(
    for: pet, seed: dragTestTarget(1), pointer: CGPoint(x: 200, y: 200))
  try await eventually {
    snapshot.hitTest(at: CGPoint(x: 200, y: 200), below: 0) == 1
  }

  let evaluation = controller.evaluateDrop(dragged: true, at: CGPoint(x: 200, y: 200))
  let pendingDrop = try #require(evaluation.pendingDrop)
  #expect(pendingDrop.windowID == 2)
  let resolved = await controller.targets.resolveDrop(pendingDrop)
  #expect(resolved?.windowID == 2)
}

@Test @MainActor
func radialSelectionCancelsWhenUnderlyingTargetChangesBeforeDrop() async throws {
  let liveWindows = WindowHitTestProbe()
  liveWindows.frontmost = 1
  let snapshot = DragWindowSnapshot(load: { _ in
    [
      DragWindowRegion(windowID: 1, frame: CGRect(x: 0, y: 0, width: 900, height: 700)),
      DragWindowRegion(windowID: 2, frame: CGRect(x: 0, y: 0, width: 900, height: 700)),
    ]
  })
  let controller = CompanionDragTargetingController(
    metrics: DragResponseMetrics(enabled: false),
    snapshot: snapshot,
    dropHitTest: { point, below in liveWindows.hit(point, below: below) },
    lookup: { id, _ in dragTestTarget(id) },
    radialDwellDelay: 0.02)
  let pet = CompanionInstance(
    definition: try CharacterCatalog().characters[0],
    rig: CatRig(),
    size: 64,
    seed: 1,
    transitions: TransitionLibrary())
  defer {
    controller.stop()
    pet.hud.close()
    pet.presentation.close()
  }
  controller.companionLookup = { [weak pet] id in
    pet?.definition.id == id ? pet : nil
  }
  controller.start()

  let anchor = CGPoint(x: 400, y: 400)
  pet.pickupPosition = CGPoint(x: 100, y: 100)
  pet.place(at: anchor)
  pet.isPickedUp = true

  controller.beginDrag(for: pet, seed: dragTestTarget(1), pointer: anchor)
  controller.updateDrag(for: pet, at: anchor)
  // Wait for dwell task to open the radial wheel for window 1.
  try await eventually {
    controller.diagnostics.wheel && controller.diagnostics.windowID == 1
  }

  let screen =
    NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame
    ?? NSScreen.main?.visibleFrame
    ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
  let layout = RadialSkillMenuLayout(center: anchor, visibleFrame: screen)
  let snapBubble = try #require(layout.items.first { $0.skill == .snap }?.center)
  controller.updateDrag(for: pet, at: snapBubble)
  #expect(controller.hoveredSkill == .snap)

  // Window 2 moves underneath the radial wheel before mouse release.
  liveWindows.frontmost = 2
  let evaluation = controller.evaluateDrop(dragged: true, at: snapBubble)
  #expect(evaluation.selectedSkill == nil)
  #expect(evaluation.cachedTarget?.windowID != 1)
  #expect(evaluation.pendingDrop?.windowID == 2)
}
