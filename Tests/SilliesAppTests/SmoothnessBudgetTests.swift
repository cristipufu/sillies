import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor
func windowDragSmoothnessBudgetAndSinglePassPlacement() throws {
  let suiteName = "app.sillies.test.smoothness.drag.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  try enableFullCrewForTiming(in: settings)

  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let initialWindow = try fullCrewTimingWindow(settings: settings)
  controller.tracker.simulateTrackedWindow(initialWindow, windowID: 101)
  controller.tracker.stop()
  try DisplayFrameSequence.presentCreatedWindows()
  controller.smoothnessMetrics.reset()

  let primaryView = try #require(controller.primaryCompanionView)
  let maskLayer = try #require(primaryView.layer?.mask as? CAShapeLayer)
  let initialMaskPath = try #require(maskLayer.path)

  let initialPlacements = controller.totalPlacementCount
  let initialFeedbackAnimations = controller.rigFeedbackAnimationCount
  let frameCount = 240

  try DisplayFrameSequence.run(count: frameCount) { frameIndex in
    let progress = Double(frameIndex) / Double(frameCount)
    let movedWindow = initialWindow.offsetBy(
      dx: sin(progress * .pi * 4) * TimingWindowLayout.horizontalTravel + 0.33,
      dy: cos(progress * .pi * 2) * 45 - 0.17)
    controller.tracker.simulateTrackedWindow(movedWindow, windowID: 101)

    for attachment in controller.attachmentDiagnostics {
      #expect(attachment.visible)
      #expect(abs(attachment.point.y - (movedWindow.maxY + 1)) < 0.01)
    }
  }

  let placementsDuringDrag = controller.totalPlacementCount - initialPlacements
  let feedbackAnimationsDuringDrag =
    controller.rigFeedbackAnimationCount - initialFeedbackAnimations
  let finalMaskPath = try #require(maskLayer.path)

  #expect(placementsDuringDrag == frameCount * settings.enabledCharacters.count)
  #expect(initialMaskPath === finalMaskPath)
  // Feedback is capped at 30 Hz on this 120 Hz fixture, per companion.
  let maximumFeedbackFraction = 0.25
  let maximumFeedbackUpdates =
    Double(frameCount * settings.enabledCharacters.count)
    * maximumFeedbackFraction
  #expect(Double(feedbackAnimationsDuringDrag) < maximumFeedbackUpdates)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowMove) == frameCount)
  #expect(
    controller.smoothnessMetrics.isWithinBudget(for: .windowMove, budget: .fullCrew),
    "\(controller.smoothnessMetrics.diagnosticReport)")
}

@Test @MainActor
func windowResizeSmoothnessBudgetAndCompactionQuantization() throws {
  let suiteName = "app.sillies.test.smoothness.resize.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  try enableFullCrewForTiming(in: settings)

  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let initialWindow = try fullCrewTimingWindow(settings: settings)
  controller.tracker.simulateTrackedWindow(initialWindow, windowID: 202)
  controller.tracker.stop()
  try DisplayFrameSequence.presentCreatedWindows()
  controller.smoothnessMetrics.reset()

  let initialPlacements = controller.totalPlacementCount
  let frameCount = 120

  try DisplayFrameSequence.run(count: frameCount) { frameIndex in
    let deltaWidth = sin(Double(frameIndex) * 0.1) * TimingWindowLayout.horizontalTravel
    let deltaHeight = cos(Double(frameIndex) * 0.1) * 40
    let resizedWindow = CGRect(
      x: initialWindow.minX,
      y: initialWindow.minY,
      width: initialWindow.width + deltaWidth,
      height: initialWindow.height + deltaHeight)
    controller.tracker.simulateTrackedWindow(resizedWindow, windowID: 202)
  }

  let placementsDuringResize = controller.totalPlacementCount - initialPlacements
  #expect(placementsDuringResize == frameCount * settings.enabledCharacters.count)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowResize) == frameCount)
  #expect(
    controller.smoothnessMetrics.isWithinBudget(for: .windowResize, budget: .fullCrew),
    "\(controller.smoothnessMetrics.diagnosticReport)")

  // Sub-pixel vertical movement near the menu bar must quantize compacted presentationSize
  // so NSPanel backing stores are not resized on fractional jitter.
  let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let nearTopWindowA = CGRect(x: 200, y: 200, width: 800, height: 640.1)
  let nearTopWindowB = CGRect(x: 200, y: 200, width: 800, height: 640.3)
  let surfaceA = PerchSurface(
    window: nearTopWindowA, visibleFrame: visibleFrame, characterSize: 64)
  let surfaceB = PerchSurface(
    window: nearTopWindowB, visibleFrame: visibleFrame, characterSize: 64)
  #expect(surfaceA.presentationSize < 64)
  #expect(surfaceA.presentationSize == surfaceB.presentationSize)
}

@Test @MainActor
func windowSwitchSmoothnessBudgetAndZeroFlickerAppTransition() throws {
  let suiteName = "app.sillies.test.smoothness.switch.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  try enableFullCrewForTiming(in: settings)

  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let firstWindow = try fullCrewTimingWindow(settings: settings)
  controller.tracker.simulateTrackedWindow(firstWindow, windowID: 301)
  #expect(controller.attachmentDiagnostics.allSatisfy { $0.visible })
  let initialInstallations = controller.interactionMonitorInstallations

  // Simulate switching to another application while WindowServer discovery is in flight:
  // companions must not flicker hidden or reinstall NSEvent monitors during the async hop.
  controller.tracker.simulateApplicationSwitchInFlight(
    processID: 999,
    applicationName: "Second App",
    bundleIdentifier: "app.sillies.second")
  #expect(controller.tracker.isAwaitingApplicationWindow)
  #expect(controller.attachmentDiagnostics.allSatisfy { $0.visible })
  #expect(controller.interactionMonitorInstallations == initialInstallations)

  controller.tracker.stop()
  try DisplayFrameSequence.presentCreatedWindows()
  controller.smoothnessMetrics.reset()
  let initialPlacements = controller.totalPlacementCount
  let switchCount = 40

  try DisplayFrameSequence.run(count: switchCount) { switchIndex in
    let nextWindow = CGRect(
      x: firstWindow.minX + Double((switchIndex % 5) * 10),
      y: firstWindow.minY + Double((switchIndex % 3) * 20),
      width: firstWindow.width + Double((switchIndex % 4) * 10),
      height: firstWindow.height)
    controller.tracker.simulateTrackedWindow(
      nextWindow,
      windowID: CGWindowID(301 + switchIndex))
  }

  let placementsDuringSwitches = controller.totalPlacementCount - initialPlacements
  #expect(placementsDuringSwitches == switchCount * settings.enabledCharacters.count)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowSwitch) == switchCount)
  #expect(
    controller.smoothnessMetrics.isWithinBudget(for: .windowSwitch, budget: .fullCrew),
    "\(controller.smoothnessMetrics.diagnosticReport)")

  // Minimizing or closing the last window and restoring a window must also stay within the
  // windowSwitch frame budget.
  controller.tracker.stop()
  try DisplayFrameSequence.presentCreatedWindows()
  controller.smoothnessMetrics.reset()
  try DisplayFrameSequence.run(count: 20) { cycle in
    controller.tracker.simulateTrackedWindow(nil, windowID: nil)
    let restoredWindow = CGRect(
      x: firstWindow.minX + Double((cycle % 4) * 10),
      y: firstWindow.minY + Double((cycle % 3) * 20),
      width: firstWindow.width,
      height: firstWindow.height)
    controller.tracker.simulateTrackedWindow(restoredWindow, windowID: CGWindowID(500 + cycle))
  }
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowSwitch) == 40)
  #expect(
    controller.smoothnessMetrics.isWithinBudget(for: .windowSwitch, budget: .fullCrew),
    "\(controller.smoothnessMetrics.diagnosticReport)")
}

@Test(arguments: [
  "mochi", "kiko", "pogo", "bolt", "boo", "bloop", "sprout", "pip", "pebble", "taro", "nib",
  "mallow", "novi", "lumi", "rook", "flick", "leon", "gizmo", "orbit", "mimo",
]) @MainActor
func companionDragSmoothnessBudgetAndUnclippedMaskStability(characterID: String) throws {
  let diagnostics = DragFrameDiagnostics.fromEnvironment()
  let suiteName = "app.sillies.test.smoothness.companion.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  settings.enabledCharacters = [characterID]

  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.smoothnessMetrics.isEnabled = true
  controller.dragTargeting.metrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let windowFrame = CGRect(x: 200, y: 180, width: 800, height: 520)
  controller.tracker.simulateTrackedWindow(windowFrame, windowID: 401)

  let primaryView = try #require(controller.primaryCompanionView)
  primaryView.onPickup?()
  let maskLayer = try #require(primaryView.layer?.mask as? CAShapeLayer)
  let pickupMaskPath = try #require(maskLayer.path)

  controller.tracker.stop()
  try DisplayFrameSequence.presentCreatedWindows()
  controller.smoothnessMetrics.reset()
  let frameCount = 120

  try DisplayFrameSequence.run(count: frameCount) { frameIndex in
    let delta = CGPoint(
      x: Double(frameIndex) * 1.5,
      y: -Double(frameIndex) * 2.5)
    if let diagnostics {
      diagnostics.measure(frame: frameIndex) { primaryView.onDrag?(delta) }
    } else {
      primaryView.onDrag?(delta)
    }
  }
  primaryView.onDrop?(true)

  let postDragMaskPath = try #require(maskLayer.path)
  #expect(pickupMaskPath === postDragMaskPath)
  #expect(controller.dragTargeting.usesHardwareBorderOutline)
  #expect(controller.smoothnessMetrics.sampleCount(for: .companionDrag) == frameCount)
  if let diagnostics {
    print(
      "DRAG \(characterID): \(diagnostics.summary); \(controller.smoothnessMetrics.diagnosticReport); \(controller.dragTimingSummary)"
    )
  }
  #expect(
    controller.smoothnessMetrics.isWithinBudget(for: .companionDrag),
    Comment(
      rawValue: controller.smoothnessMetrics.diagnosticReport + "; " + controller.dragTimingSummary)
  )
}

@MainActor
private func enableFullCrewForTiming(in settings: AppSettings) throws {
  settings.enabledCharacters = Set(try CharacterCatalog().characters.map(\.id))
  // Fit the complete crew into the smallest resize fixture. Individual drag cases
  // retain the default size; all timing thresholds and native placement counts are unchanged.
  settings.size = AppSettings.minSize
}

private enum TimingWindowLayout {
  static let horizontalInset: CGFloat = 72
  static let horizontalTravel: CGFloat = 40
  static let bottomInset: CGFloat = 100
  static let reservedHeadroom: CGFloat = 200
  static let maximumHeight: CGFloat = 500
}

/// Keep every character visible throughout the timing workload. The old fixed-width windows
/// could no longer hold the expanded roster and measured overflow transitions instead of movement.
@MainActor private func fullCrewTimingWindow(settings: AppSettings) throws -> CGRect {
  let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
  let visible = CompanionPanel.visibleFrame(for: screen)
  let frame = CGRect(
    x: visible.minX + TimingWindowLayout.horizontalInset,
    y: visible.minY + TimingWindowLayout.bottomInset,
    width: visible.width - 2 * TimingWindowLayout.horizontalInset,
    height: min(
      TimingWindowLayout.maximumHeight, visible.height - TimingWindowLayout.reservedHeadroom)
  )
  let smallest = CGRect(
    origin: frame.origin,
    size: CGSize(width: frame.width - TimingWindowLayout.horizontalTravel, height: frame.height))
  let surface = PerchSurface(window: smallest, visibleFrame: visible, characterSize: settings.size)
  let requiredSpan =
    Double(settings.enabledCharacters.count - 1)
    * PerchSpacing.separation(between: settings.size, and: settings.size)
  try #require(
    surface.edge == .top && surface.spanLength >= requiredSpan,
    "The display must fit the complete crew before measuring one placement per visible companion.")
  return frame
}
