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
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  var iterations = 0
  while !(await condition()), iterations < 20 || ContinuousClock.now < deadline {
    iterations += 1
    try await Task.sleep(for: .milliseconds(2))
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

@Test @MainActor
func floatingForeignWindowsLikeBrowserPictureInPictureAreTrackableBelowCompanionOverlays() throws {
  let floatingLayer = Int(CGWindowLevelForKey(.floatingWindow))
  let ownPID = ProcessInfo.processInfo.processIdentifier
  let foreignPID = ownPID + 100

  #expect(WindowServerSource.isTrackableWindowLayer(0, ownerPID: ownPID))
  #expect(WindowServerSource.isTrackableWindowLayer(0, ownerPID: foreignPID))
  #expect(WindowServerSource.isTrackableWindowLayer(floatingLayer, ownerPID: foreignPID))
  #expect(!WindowServerSource.isTrackableWindowLayer(floatingLayer, ownerPID: ownPID))
  #expect(CompanionPanel.overlayLevel.rawValue > floatingLayer)
  // Companions on normal windows sit above normal windows (0) and below floating windows (3),
  // while companions on floating windows (or picked up) sit above floating windows (3).
  let normalCompanionLevel = CompanionPanel.overlayLevel(forWindowLayer: 0).rawValue
  let normalHUDLevel = CompanionPanel.hudLevel(forWindowLayer: 0).rawValue
  let floatingCompanionLevel = CompanionPanel.overlayLevel(forWindowLayer: floatingLayer).rawValue
  let pickedUpCompanionLevel = CompanionPanel.overlayLevel(forWindowLayer: 0, isPickedUp: true)
    .rawValue
  #expect(normalCompanionLevel > WindowServerSource.normalWindowLayer)
  #expect(normalCompanionLevel < floatingLayer)
  #expect(normalHUDLevel > normalCompanionLevel)
  #expect(normalHUDLevel < floatingLayer)
  #expect(floatingCompanionLevel > floatingLayer)
  #expect(pickedUpCompanionLevel > floatingLayer)

  // 1. Standard layer-0 apps (e.g. Ghostty) always trust WindowServer front-to-back order
  // even if Accessibility reports a stale/background window frame.
  let frontNormal = WindowServerSource.Candidate(
    id: 10, layer: 0, frame: CGRect(x: 500, y: 200, width: 900, height: 600))
  let backNormal = WindowServerSource.Candidate(
    id: 11, layer: 0, frame: CGRect(x: 60, y: 150, width: 1100, height: 700))
  let chosenNormal = WindowServerSource.chooseCandidate(
    from: [frontNormal, backNormal],
    preferredFrame: backNormal.frame,
    preferredPoint: nil,
    currentWindowID: 11)
  #expect(chosenNormal?.id == 10)

  // 2. When an app has both a floating PiP window (layer 3) and a main browser window (layer 0),
  // click point and AX focus disambiguate them, and currentWindowID is retained across drags.
  let meetPiP = WindowServerSource.Candidate(
    id: 20, layer: floatingLayer, frame: CGRect(x: 900, y: 250, width: 500, height: 600))
  let mainBrowser = WindowServerSource.Candidate(
    id: 21, layer: 0, frame: CGRect(x: 0, y: 33, width: 1512, height: 867))
  let chromeCandidates = [meetPiP, mainBrowser]

  // Clicking inside the Meet PiP window selects Meet.
  #expect(
    WindowServerSource.chooseCandidate(
      from: chromeCandidates,
      preferredFrame: nil,
      preferredPoint: CGPoint(x: 1100, y: 400),
      currentWindowID: 21)?.id == 20)

  // Clicking on the main browser window outside Meet selects the main browser window.
  #expect(
    WindowServerSource.chooseCandidate(
      from: chromeCandidates,
      preferredFrame: nil,
      preferredPoint: CGPoint(x: 200, y: 400),
      currentWindowID: 20)?.id == 21)

  // Once the main browser window is active, subsequent discovery ticks keep it active
  // even though Meet remains at layer 3 in front.
  #expect(
    WindowServerSource.chooseCandidate(
      from: chromeCandidates,
      preferredFrame: nil,
      preferredPoint: nil,
      currentWindowID: 21)?.id == 21)

  // 3. System / OS popups and confirmation dialogs are excluded, while verified standard
  // floating windows (like Google Meet) remain eligible.
  #expect(
    TrackableApplicationPolicy.isTrackable(
      activationPolicy: .regular,
      bundleIdentifier: "com.google.Chrome",
      bundlePath: "/Applications/Google Chrome.app"))
  #expect(
    TrackableApplicationPolicy.isTrackable(
      activationPolicy: .regular,
      bundleIdentifier: "com.apple.finder",
      bundlePath: "/System/Library/CoreServices/Finder.app"))
  #expect(
    !TrackableApplicationPolicy.isTrackable(
      activationPolicy: .accessory,
      bundleIdentifier: "com.apple.UserNotificationCenter",
      bundlePath: "/System/Library/CoreServices/UserNotificationCenter.app"))
  #expect(
    !TrackableApplicationPolicy.isTrackable(
      activationPolicy: .regular,
      bundleIdentifier: "com.apple.coreservices.uiagent",
      bundlePath: "/System/Library/CoreServices/CoreServicesUIAgent.app"))

  let permissionBubble = WindowServerSource.Candidate(
    id: 22, layer: floatingLayer, frame: CGRect(x: 920, y: 280, width: 380, height: 280))
  let confirmationAlert = WindowServerSource.Candidate(
    id: 23, layer: WindowServerSource.normalWindowLayer,
    frame: CGRect(x: 520, y: 300, width: 420, height: 280))
  let passwordAutocompletePopup = WindowServerSource.Candidate(
    id: 24, layer: WindowServerSource.normalWindowLayer,
    frame: CGRect(x: 600, y: 360, width: 240, height: 160))
  let largeInteriorAutocompletePopup = WindowServerSource.Candidate(
    id: 25, layer: WindowServerSource.normalWindowLayer,
    frame: CGRect(x: 420, y: 280, width: 320, height: 240))
  let chromeOmniboxPopup = WindowServerSource.Candidate(
    id: 26, layer: WindowServerSource.normalWindowLayer,
    frame: CGRect(x: 136, y: 58, width: 1043, height: 218))
  #expect(!WindowServerSource.isTrackableWindowSize(passwordAutocompletePopup.frame.size))
  #expect(WindowServerSource.isTrackableWindowSize(CGSize(width: 300, height: 220)))
  #expect(WindowServerSource.isTrackableWindowSize(meetPiP.frame.size))
  let roleSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [meetPiP.frame, mainBrowser.frame],
    nonStandardWindowFrames: [confirmationAlert.frame],
    hasVerifiedWindowList: true)

  // Floating permission bubble (not in standardWindowFrames), confirmation alert (in
  // nonStandardWindowFrames), and both small and large interior autocomplete/omnibox popup windows
  // are filtered out; Meet PiP (in standardWindowFrames) wins.
  let chosenWithPopups = WindowServerSource.chooseCandidate(
    from: [
      passwordAutocompletePopup, largeInteriorAutocompletePopup, chromeOmniboxPopup,
      permissionBubble, confirmationAlert, meetPiP, mainBrowser,
    ],
    preferredFrame: nil,
    preferredPoint: nil,
    currentWindowID: nil,
    roleSnapshot: roleSnapshot,
    requiresVerifiedFloatingRole: true)
  #expect(chosenWithPopups?.id == 20)

  // Even when Accessibility is disabled (roleSnapshot == nil) or after dragging the browser window
  // before AX refreshes, Chrome's URL/search omnibox popup inside the browser window is excluded.
  let movedMainBrowser = WindowServerSource.Candidate(
    id: 21, layer: 0, frame: mainBrowser.frame.offsetBy(dx: 120, dy: 60))
  let movedOmniboxPopup = WindowServerSource.Candidate(
    id: 26, layer: 0, frame: chromeOmniboxPopup.frame.offsetBy(dx: 120, dy: 60))
  #expect(
    WindowServerSource.chooseCandidate(
      from: [movedOmniboxPopup, movedMainBrowser],
      preferredFrame: nil,
      preferredPoint: nil,
      currentWindowID: 21,
      roleSnapshot: nil,
      requiresVerifiedFloatingRole: false)?.id == 21)
  let staleMovedBrowserSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [mainBrowser.frame],
    nonStandardWindowFrames: [],
    hasVerifiedWindowList: true,
    hasExactStandardWindowFrames: false)
  #expect(
    WindowServerSource.chooseCandidate(
      from: [movedOmniboxPopup, movedMainBrowser],
      preferredFrame: nil,
      preferredPoint: nil,
      currentWindowID: 21,
      roleSnapshot: staleMovedBrowserSnapshot,
      requiresVerifiedFloatingRole: true)?.id == 21)

  // 4. Clicking the exterior resize border (within hitSlop outside maxX, directly over the
  // background window) and resizing the active window keeps companions on the active window.
  let resizeBorderClick = CGPoint(
    x: meetPiP.frame.maxX + 6,
    y: meetPiP.frame.midY)
  #expect(mainBrowser.frame.contains(resizeBorderClick))
  #expect(!meetPiP.frame.contains(resizeBorderClick))
  let chosenOnResizeBorder = WindowServerSource.chooseCandidate(
    from: chromeCandidates,
    preferredFrame: nil,
    preferredPoint: resizeBorderClick,
    currentWindowID: 20,
    roleSnapshot: roleSnapshot,
    requiresVerifiedFloatingRole: true)
  #expect(chosenOnResizeBorder?.id == 20)

  // During active resize, even if the active window shrinks below minimumTrackableWindowSize
  // before AX roleSnapshot updates, currentWindowID remains locked to the window being resized.
  let shrunkenMeet = WindowServerSource.Candidate(
    id: 20, layer: floatingLayer, frame: CGRect(x: 900, y: 250, width: 220, height: 160))
  let chosenDuringResize = WindowServerSource.chooseCandidate(
    from: [shrunkenMeet, mainBrowser],
    preferredFrame: mainBrowser.frame,
    preferredPoint: nil,
    currentWindowID: 20,
    roleSnapshot: roleSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: true)
  #expect(chosenDuringResize?.id == 20)

  // 5. Resizing a standard normal-layer window inward when a background window of the same
  // app is behind the initial click point and roleSnapshot still holds the pre-resize frame
  // must keep the active front window instead of switching to the background window.
  let shrunkenFrontNormal = WindowServerSource.Candidate(
    id: 10, layer: 0, frame: CGRect(x: 580, y: 200, width: 820, height: 600))
  let preResizeClickAtOldLeftEdge = CGPoint(
    x: frontNormal.frame.minX + 2, y: frontNormal.frame.midY)
  #expect(!shrunkenFrontNormal.frame.contains(preResizeClickAtOldLeftEdge))
  #expect(backNormal.frame.contains(preResizeClickAtOldLeftEdge))
  let normalRoleSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [frontNormal.frame, backNormal.frame],
    nonStandardWindowFrames: [])
  let chosenNormalDuringInwardResize = WindowServerSource.chooseCandidate(
    from: [shrunkenFrontNormal, backNormal],
    preferredFrame: backNormal.frame,
    preferredPoint: preResizeClickAtOldLeftEdge,
    currentWindowID: nil,
    roleSnapshot: normalRoleSnapshot,
    requiresVerifiedFloatingRole: true)
  #expect(chosenNormalDuringInwardResize?.id == 10)

  // 6. Moving (dragging) a standard normal-layer window when a second standard window is
  // stationary in the background and roleSnapshot still holds the pre-drag origin must keep
  // the moved front window instead of rejecting it or switching to the background window.
  let movedFrontNormal = WindowServerSource.Candidate(
    id: 10, layer: 0, frame: frontNormal.frame.offsetBy(dx: 140, dy: -85))
  let chosenNormalDuringMove = WindowServerSource.chooseCandidate(
    from: [movedFrontNormal, backNormal],
    preferredFrame: backNormal.frame,
    preferredPoint: nil,
    currentWindowID: nil,
    roleSnapshot: normalRoleSnapshot,
    requiresVerifiedFloatingRole: true)
  #expect(chosenNormalDuringMove?.id == 10)

  // 6b. Minimizing or closing the currently tracked front window while its surface is still
  // animating out in WindowServer must immediately switch to the remaining standard window (or nil
  // when the last window closes) without waiting for the Dock genie / close fade animation.
  let minimizedFrontSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [backNormal.frame],
    nonStandardWindowFrames: [frontNormal.frame],
    hasVerifiedWindowList: true)
  let chosenAfterFrontMinimized = WindowServerSource.chooseCandidate(
    from: [frontNormal, backNormal],
    preferredFrame: backNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: minimizedFrontSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenAfterFrontMinimized?.id == 11)

  let closedFrontSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [backNormal.frame],
    nonStandardWindowFrames: [],
    hasVerifiedWindowList: true)
  let chosenAfterFrontClosed = WindowServerSource.chooseCandidate(
    from: [frontNormal, backNormal],
    preferredFrame: backNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: closedFrontSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenAfterFrontClosed?.id == 11)

  let closedLastWindowSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [],
    nonStandardWindowFrames: [],
    hasVerifiedWindowList: true)
  let chosenAfterLastWindowClosed = WindowServerSource.chooseCandidate(
    from: [frontNormal],
    preferredFrame: nil,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: closedLastWindowSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenAfterLastWindowClosed == nil)

  // 6c. During the ~550ms macOS Dock genie minimize animation, WindowServer warps CGWindowBounds
  // toward the Dock before kAXWindowMiniaturizedNotification fires. When not actively manipulating
  // a window (isManipulatingWindow == false), genie-warped bounds must never be mistaken for a
  // user resize or accepted via a fallback to unverified candidates.
  let verifiedSingleWindowSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [frontNormal.frame],
    nonStandardWindowFrames: [],
    hasVerifiedWindowList: true)
  let genieInitialWobble = WindowServerSource.Candidate(
    id: 10,
    layer: 0,
    frame: CGRect(
      x: frontNormal.frame.minX,
      y: frontNormal.frame.minY,
      width: frontNormal.frame.width + 3,
      height: frontNormal.frame.height))
  let chosenDuringGeniePreStretch = WindowServerSource.chooseCandidate(
    from: [genieInitialWobble],
    preferredFrame: frontNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: verifiedSingleWindowSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenDuringGeniePreStretch?.frame == frontNormal.frame)

  let geniePhase1Stretch = WindowServerSource.Candidate(
    id: 10,
    layer: 0,
    frame: CGRect(
      x: frontNormal.frame.minX,
      y: frontNormal.frame.minY,
      width: frontNormal.frame.width + 60,
      height: frontNormal.frame.height + 1))
  let chosenDuringGeniePhase1SingleWindow = WindowServerSource.chooseCandidate(
    from: [geniePhase1Stretch],
    preferredFrame: frontNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: verifiedSingleWindowSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenDuringGeniePhase1SingleWindow == nil)

  let genieMidAirMesh = WindowServerSource.Candidate(
    id: 10,
    layer: 0,
    frame: CGRect(x: 939, y: 616, width: 436, height: 335))
  let chosenDuringGenieMidAirSingleWindow = WindowServerSource.chooseCandidate(
    from: [genieMidAirMesh],
    preferredFrame: frontNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: verifiedSingleWindowSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenDuringGenieMidAirSingleWindow == nil)

  let verifiedTwoWindowSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [frontNormal.frame, backNormal.frame],
    nonStandardWindowFrames: [],
    hasVerifiedWindowList: true)
  let chosenDuringGeniePhase1TwoWindows = WindowServerSource.chooseCandidate(
    from: [geniePhase1Stretch, backNormal],
    preferredFrame: frontNormal.frame,
    preferredPoint: nil,
    currentWindowID: 10,
    roleSnapshot: verifiedTwoWindowSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenDuringGeniePhase1TwoWindows?.id == 11)

  // 6d. A minimized or non-standard window sharing the exact same rect as an open standard window
  // must never disqualify the open standard window.
  let overlappingMinimizedSnapshot = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [frontNormal.frame],
    nonStandardWindowFrames: [frontNormal.frame],
    hasVerifiedWindowList: true)
  let chosenWithOverlappingMinimizedRect = WindowServerSource.chooseCandidate(
    from: [frontNormal],
    preferredFrame: frontNormal.frame,
    preferredPoint: nil,
    currentWindowID: nil,
    roleSnapshot: overlappingMinimizedSnapshot,
    requiresVerifiedFloatingRole: true,
    isManipulatingWindow: false)
  #expect(chosenWithOverlappingMinimizedRect?.id == 10)

  // 7. Non-structural AX notifications (move, resize, title, selection) must never re-query
  // the target application's window hierarchy during a window drag.
  #expect(AccessibilityWindowSource.isNonStructuralWindowNotification(kAXMovedNotification))
  #expect(AccessibilityWindowSource.isNonStructuralWindowNotification(kAXResizedNotification))
  #expect(AccessibilityWindowSource.isNonStructuralWindowNotification(kAXTitleChangedNotification))
  #expect(
    AccessibilityWindowSource.isNonStructuralWindowNotification(
      kAXSelectedChildrenChangedNotification))
  #expect(
    !AccessibilityWindowSource.isNonStructuralWindowNotification(
      AccessibilityWindowSource.activationReason))
  #expect(
    !AccessibilityWindowSource.isNonStructuralWindowNotification(
      AccessibilityWindowSource.sampleReason))
  #expect(
    !AccessibilityWindowSource.isNonStructuralWindowNotification(
      kAXFocusedWindowChangedNotification))

  // 8. Pure fractional window translation must not rebuild the companion's worldMask path.
  let rig = CatRig()
  let view = CompanionView(rig: rig, size: 64)
  let panel = CompanionPanel(view: view)
  defer { panel.close() }
  let display = CGRect(x: 0, y: 0, width: 1512, height: 945)
  let initialAttachedWindow = CGRect(x: 200.0, y: 200.0, width: 800.0, height: 500.0)
  view.configureSurface(pose: .standing, window: initialAttachedWindow, display: display)
  let initialLayout = view.panelLayout(
    at: CGPoint(x: 500.0, y: initialAttachedWindow.maxY + 1), attached: true)
  panel.setFrame(initialLayout.frame, display: false)
  view.applyPanelLayout(initialLayout)
  view.updateWorldMask()
  let maskLayer = try #require(view.layer?.mask as? CAShapeLayer)
  let initialPath = try #require(maskLayer.path)

  let translatedWindow = initialAttachedWindow.offsetBy(dx: 17.3333333333, dy: -9.6666666667)
  view.configureSurface(pose: .standing, window: translatedWindow, display: display)
  let translatedLayout = view.panelLayout(
    at: CGPoint(x: 517.3333333333, y: translatedWindow.maxY + 1), attached: true)
  panel.setFrame(translatedLayout.frame, display: false)
  view.applyPanelLayout(translatedLayout)
  view.updateWorldMask()
  let translatedPath = try #require(maskLayer.path)
  #expect(initialPath === translatedPath)
}
