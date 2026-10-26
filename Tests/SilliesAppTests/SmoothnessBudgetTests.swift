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
  settings.enabledCharacters = ["mochi", "kiko"]

  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let initialWindow = CGRect(x: 180, y: 180, width: 760, height: 520)
  controller.tracker.simulateTrackedWindow(initialWindow, windowID: 101)
  controller.smoothnessMetrics.reset()

  let primaryView = try #require(controller.primaryCompanionView)
  let maskLayer = try #require(primaryView.layer?.mask as? CAShapeLayer)
  let initialMaskPath = try #require(maskLayer.path)

  let initialPlacements = controller.totalPlacementCount
  let initialFeedbackAnimations = controller.rigFeedbackAnimationCount
  let frameCount = 240

  for frameIndex in 1...frameCount {
    let progress = Double(frameIndex) / Double(frameCount)
    let movedWindow = initialWindow.offsetBy(
      dx: sin(progress * .pi * 4) * 140 + 0.33,
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

  #expect(placementsDuringDrag == frameCount * 2)
  #expect(initialMaskPath === finalMaskPath)
  #expect(feedbackAnimationsDuringDrag < frameCount)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowMove) == frameCount)
  #expect(controller.smoothnessMetrics.isWithinBudget(for: .windowMove))
}

@Test @MainActor
func windowResizeSmoothnessBudgetAndCompactionQuantization() throws {
  let suiteName = "app.sillies.test.smoothness.resize.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  settings.enabledCharacters = ["mochi", "kiko"]

  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let initialWindow = CGRect(x: 160, y: 160, width: 720, height: 500)
  controller.tracker.simulateTrackedWindow(initialWindow, windowID: 202)
  controller.smoothnessMetrics.reset()

  let initialPlacements = controller.totalPlacementCount
  let frameCount = 120

  for frameIndex in 1...frameCount {
    let deltaWidth = sin(Double(frameIndex) * 0.1) * 120
    let deltaHeight = cos(Double(frameIndex) * 0.1) * 40
    let resizedWindow = CGRect(
      x: initialWindow.minX,
      y: initialWindow.minY,
      width: initialWindow.width + deltaWidth,
      height: initialWindow.height + deltaHeight)
    controller.tracker.simulateTrackedWindow(resizedWindow, windowID: 202)
  }

  let placementsDuringResize = controller.totalPlacementCount - initialPlacements
  #expect(placementsDuringResize == frameCount * 2)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowResize) == frameCount)
  #expect(controller.smoothnessMetrics.isWithinBudget(for: .windowResize))

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
  settings.enabledCharacters = ["mochi", "kiko"]

  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let firstWindow = CGRect(x: 120, y: 150, width: 780, height: 520)
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

  controller.smoothnessMetrics.reset()
  let initialPlacements = controller.totalPlacementCount
  let switchCount = 40

  for switchIndex in 1...switchCount {
    let nextWindow = CGRect(
      x: 100 + Double((switchIndex % 5) * 70),
      y: 120 + Double((switchIndex % 3) * 50),
      width: 760 + Double((switchIndex % 4) * 30),
      height: 500)
    controller.tracker.simulateTrackedWindow(
      nextWindow,
      windowID: CGWindowID(301 + switchIndex))
  }

  let placementsDuringSwitches = controller.totalPlacementCount - initialPlacements
  #expect(placementsDuringSwitches == switchCount * 2)
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowSwitch) == switchCount)
  #expect(controller.smoothnessMetrics.isWithinBudget(for: .windowSwitch))

  // Minimizing or closing the last window and restoring a window must also stay within the
  // windowSwitch frame budget.
  controller.smoothnessMetrics.reset()
  for cycle in 1...20 {
    controller.tracker.simulateTrackedWindow(nil, windowID: nil)
    let restoredWindow = CGRect(
      x: 160 + Double((cycle % 4) * 50),
      y: 140 + Double((cycle % 3) * 40),
      width: 820,
      height: 520)
    controller.tracker.simulateTrackedWindow(restoredWindow, windowID: CGWindowID(500 + cycle))
  }
  #expect(controller.smoothnessMetrics.sampleCount(for: .windowSwitch) == 40)
  #expect(controller.smoothnessMetrics.isWithinBudget(for: .windowSwitch))
}

@Test @MainActor
func companionDragSmoothnessBudgetAndUnclippedMaskStability() throws {
  let suiteName = "app.sillies.test.smoothness.companion.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = false
  settings.enabledCharacters = ["kiko"]

  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.smoothnessMetrics.isEnabled = true
  controller.start()
  defer { controller.stop() }

  let windowFrame = CGRect(x: 200, y: 180, width: 800, height: 520)
  controller.tracker.simulateTrackedWindow(windowFrame, windowID: 401)

  let primaryView = try #require(controller.primaryCompanionView)
  primaryView.onPickup?()
  let maskLayer = try #require(primaryView.layer?.mask as? CAShapeLayer)
  let pickupMaskPath = try #require(maskLayer.path)

  controller.smoothnessMetrics.reset()
  let frameCount = 120

  for frameIndex in 1...frameCount {
    let delta = CGPoint(
      x: Double(frameIndex) * 1.5,
      y: -Double(frameIndex) * 2.5)
    primaryView.onDrag?(delta)
  }
  primaryView.onDrop?(true)

  let postDragMaskPath = try #require(maskLayer.path)
  #expect(pickupMaskPath === postDragMaskPath)
  #expect(controller.dragTargeting.usesHardwareBorderOutline)
  #expect(controller.smoothnessMetrics.sampleCount(for: .companionDrag) == frameCount)
  #expect(controller.smoothnessMetrics.isWithinBudget(for: .companionDrag))
}
