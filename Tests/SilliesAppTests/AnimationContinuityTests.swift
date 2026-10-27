import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor
func interruptedWindowFeedbackDoesNotJumpToItsUnreachedTarget() throws {
  let rig = CatRig()
  rig.workspaceFeedback(lean: 0.2, stretch: 0.1)
  rig.workspaceFeedback(lean: 0, stretch: 0, settling: true)
  let spring = try #require(
    rig.workspaceMotion.animation(forKey: "workspaceFeedback") as? CABasicAnimation)
  let start = try #require(spring.fromValue as? NSValue).caTransform3DValue
  #expect(abs(start.m12) < 0.1)
  rig.setAttachmentPose(.hangingLeft)
  #expect(CATransform3DIsIdentity(rig.workspaceMotion.transform))
  #expect(rig.workspaceMotion.animationKeys() == nil)
}

@Test @MainActor
func unchangedBehaviorKeepsItsClipUntilPoseMotionPolicyOrResetChanges() {
  let rig = CatRig()
  let playback = BehaviorPlayback(rig: rig, characterID: "mochi")
  let library = AnimationLibrary()
  var standingStarts = 0
  var hangingStarts = 0
  var staticStarts = 0
  library.register(.walk) { _ in standingStarts += 1 }
  library.register(.climb) { _ in hangingStarts += 1 }
  library.registerReducedMotion(.climb) { _ in staticStarts += 1 }
  let state = BehaviorState(animation: .walk, expiresAt: 100)

  for _ in 0..<120 {
    playback.apply(state, library: library, reducedMotion: false)
  }
  #expect(standingStarts == 1)
  rig.setAttachmentPose(.hangingLeft)
  playback.apply(state, library: library, reducedMotion: false)
  #expect(hangingStarts == 1)
  playback.apply(state, library: library, reducedMotion: true)
  playback.apply(state, library: library, reducedMotion: true)
  #expect(staticStarts == 1)

  // Hiding clears the rig; resuming the same state must reinstall the clip.
  rig.resetPose()
  playback.apply(state, library: library, reducedMotion: false)
  #expect(hangingStarts == 2)
  playback.apply(
    BehaviorState(animation: .walk, expiresAt: 200), library: library, reducedMotion: false)
  #expect(hangingStarts == 3)
}

@Test @MainActor
func applicationDiscoveryAndUnrelatedSettingsPreservePlayingClips() throws {
  let domain = "app.sillies.test.continuity.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let settings = AppSettings(defaults: defaults)
  settings.enabledCharacters = ["mochi"]
  settings.followsWindows = true
  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.start()
  defer { controller.stop() }
  controller.tracker.simulateTrackedWindow(
    CGRect(x: 160, y: 140, width: 800, height: 480), windowID: 101)
  controller.greet()
  let view = try #require(controller.primaryCompanionView)
  let generation = view.rig.behaviorResetGeneration

  settings.activity = .calm
  #expect(view.rig.behaviorResetGeneration == generation)
  controller.tracker.simulateApplicationSwitchInFlight(processID: 999)
  #expect(view.rig.behaviorResetGeneration == generation)

  view.onPickup?()
  #expect(controller.diagnostics.movementClockRunning)
  settings.paused = true
  #expect(!controller.diagnostics.movementClockRunning)
  #expect(!controller.diagnostics.decisionClockRunning)
}

@Test @MainActor
func smoothnessBudgetRejectsOneStallAndMissingMeasurements() {
  let metrics = InteractionSmoothnessMetrics(enabled: true)
  #expect(!metrics.isWithinBudget(for: .companionDrag))
  metrics.record(0.05, for: .companionDrag)
  // A single stall must not disappear into percentiles or age out of the bounded sample buffer.
  for _ in 0..<10_000 { metrics.record(0.0001, for: .companionDrag) }
  #expect(metrics.p95Milliseconds(for: .companionDrag) < 1)
  #expect(metrics.maxMilliseconds(for: .companionDrag) == 50)
  #expect(!metrics.isWithinBudget(for: .companionDrag))
  metrics.reset()
  metrics.record(0.0001, for: .companionDrag)
  #expect(metrics.isWithinBudget(for: .companionDrag))
}

@Test @MainActor
func nativeMinimizeSuppressesLateGeometryAndTracksRestoreWhilePaused() {
  let window = NSWindow(
    contentRect: CGRect(x: 100, y: 100, width: 700, height: 400),
    styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.alphaValue = 0
  window.orderFrontRegardless()
  defer { window.close() }
  let tracker = WorkspaceTracker(useAccessibility: false)
  tracker.start()
  defer { tracker.stop() }
  tracker.simulateApplicationSwitchInFlight(processID: ProcessInfo.processInfo.processIdentifier)
  tracker.simulateTrackedWindow(window.frame, windowID: UInt32(window.windowNumber))

  let center = NotificationCenter.default
  center.post(name: NSWindow.willMiniaturizeNotification, object: window)
  #expect(tracker.windowID == nil)
  center.post(name: NSWindow.didResizeNotification, object: window)
  #expect(tracker.windowID == nil)

  tracker.configure(enabled: false, tracksWindows: true)
  center.post(name: NSWindow.didMiniaturizeNotification, object: window)
  center.post(name: NSWindow.didDeminiaturizeNotification, object: window)
  tracker.configure(enabled: true, tracksWindows: true)
  tracker.simulateApplicationSwitchInFlight(processID: ProcessInfo.processInfo.processIdentifier)
  tracker.simulateTrackedWindow(
    window.frame.offsetBy(dx: -10, dy: 0), windowID: UInt32(window.windowNumber))
  center.post(name: NSWindow.didResizeNotification, object: window)
  #expect(tracker.windowID == UInt32(window.windowNumber))
  #expect(tracker.windowFrame == window.frame)
}
