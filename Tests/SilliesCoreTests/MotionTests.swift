import CoreGraphics
import Foundation
import Testing

@testable import SilliesCore

@Test func accessibilityCoordinatesHandleDisplayAboveAndLeftOfPrimary() {
  let result = ScreenCoordinates.appKitRect(
    fromAccessibility: CGRect(x: -900, y: -500, width: 800, height: 400), primaryScreenTop: 1080)
  #expect(result == CGRect(x: -900, y: 1180, width: 800, height: 400))
}

@Test func surfaceKeepsCharactersAwayFromMenuBarAndWindowCorners() {
  let visible = CGRect(x: 0, y: 40, width: 1440, height: 1015)
  let surface = PerchSurface(
    window: CGRect(x: 100, y: 100, width: 800, height: 700), visibleFrame: visible,
    characterSize: 80)
  #expect(surface.minX == 148)
  #expect(surface.maxX == 852)
  #expect(surface.y == 801)
  #expect(surface.edge == .top)
  #expect(abs(Double(surface.point(at: -1).x) - surface.minX) < 0.0001)
  #expect(abs(Double(surface.point(at: 2).x) - surface.maxX) < 0.0001)
}

@Test func missingAndOffscreenWindowsUseSafeDesktopSurface() {
  let visible = CGRect(x: 0, y: 40, width: 1440, height: 1015)
  let desktop = PerchSurface(window: nil, visibleFrame: visible, characterSize: 80)
  #expect(desktop.y == 50)
  let offscreen = PerchSurface(
    window: CGRect(x: 3000, y: 3000, width: 500, height: 500), visibleFrame: visible,
    characterSize: 80)
  #expect(offscreen.point(at: 0.5).x == visible.midX)
  #expect(!offscreen.isAvailable)
}

@Test func tallWindowsUseOutsideSidesInsteadOfPushingCharactersIntoContent() {
  let display = CGRect(x: 0, y: 40, width: 1400, height: 900)
  let window = CGRect(x: 150, y: 100, width: 1100, height: 830)
  let left = PerchSurface(window: window, visibleFrame: display, characterSize: 70)
  let right = PerchSurface(
    window: window, visibleFrame: display, characterSize: 70, preferRight: true)
  #expect(left.edge == .left)
  #expect(right.edge == .right)
  for surface in [left, right] {
    for fraction in [0.0, 0.5, 1.0] { #expect(!window.contains(surface.point(at: fraction))) }
    #expect(abs(surface.fraction(for: surface.point(at: 0.35)) - 0.35) < 0.0001)
  }
}

@Test func screenFillingWindowDoesNotCreateAnInteriorOrDesktopPerch() {
  let display = CGRect(x: 0, y: 40, width: 1400, height: 900)
  let surface = PerchSurface(window: display, visibleFrame: display, characterSize: 70)
  #expect(surface.edge == .unavailable)
  #expect(!surface.isAvailable)
}

@Test func sideHopsTravelAwayFromWindow() {
  let tween = MotionTween(
    from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 100), at: 0, duration: 1, arcHeight: 20,
    arcDirection: CGPoint(x: -1, y: 0))
  #expect(tween.position(at: 0.5) == CGPoint(x: 80, y: 100))
}

@Test func normalizedAnchorsFollowWindowResize() {
  let visible = CGRect(x: 0, y: 0, width: 2000, height: 1200)
  let before = PerchSurface(
    window: CGRect(x: 100, y: 100, width: 600, height: 700), visibleFrame: visible,
    characterSize: 70)
  let after = PerchSurface(
    window: CGRect(x: 200, y: 100, width: 1200, height: 700), visibleFrame: visible,
    characterSize: 70)
  let fraction = before.fraction(for: before.point(at: 0.35).x)
  #expect(abs(after.fraction(for: after.point(at: fraction).x) - 0.35) < 0.0001)
}

@Test func unavailablePerchesPreserveDistinctFallbackSlots() {
  let display = CGRect(x: 0, y: 40, width: 1400, height: 900)
  let unavailable = PerchSurface(window: display, visibleFrame: display, characterSize: 64)
  let available = PerchSurface(
    window: CGRect(x: 200, y: 150, width: 800, height: 500), visibleFrame: display,
    characterSize: 64)
  let first = unavailable.fraction(for: .zero, fallback: 1.0 / 3)
  let second = unavailable.fraction(for: .zero, fallback: 2.0 / 3)
  #expect(abs(first - second) > 0.3)
  #expect(abs(available.point(at: first).x - available.point(at: second).x) > 200)
}

@Test func motionIsIndependentOfFrameSamplingAndClampsEndpoints() {
  let tween = MotionTween(
    from: CGPoint(x: 0, y: 10), to: CGPoint(x: 100, y: 10), at: 5, duration: 2, arcHeight: 20)
  #expect(tween.position(at: 0) == CGPoint(x: 0, y: 10))
  #expect(tween.position(at: 6) == CGPoint(x: 50, y: 30))
  #expect(tween.position(at: 10) == CGPoint(x: 100, y: 10))
  #expect(!tween.isComplete(at: 6.99))
  #expect(tween.isComplete(at: 7))
}

@Test func eventThrottlesAreIndependentByKind() {
  var throttle = EventThrottle()
  let first = throttle.accepts(WorkspaceEvent(.scroll, at: 1), interval: 4)
  let suppressed = throttle.accepts(WorkspaceEvent(.scroll, at: 2), interval: 4)
  let independent = throttle.accepts(WorkspaceEvent(.windowMoved, at: 2), interval: 0.2)
  let afterInterval = throttle.accepts(WorkspaceEvent(.scroll, at: 5), interval: 4)
  #expect(first)
  #expect(!suppressed)
  #expect(independent)
  #expect(afterInterval)
}

@Test func strollPlanDetectsEdgeArrivalAndBoundaryPositions() {
  let visible = CGRect(x: 0, y: 40, width: 1000, height: 800)
  let surface = PerchSurface(
    window: CGRect(x: 100, y: 100, width: 300, height: 400), visibleFrame: visible,
    characterSize: 64)
  #expect(surface.isAtBoundary(surface.start))
  #expect(surface.isAtBoundary(surface.end))
  #expect(!surface.isAtBoundary(surface.point(at: 0.5)))
  var random = SeededRandom(seed: 7)
  var reachedBoundary = false
  for _ in 0..<20 {
    let origin = surface.point(at: 0.95)
    if let plan = StrollPlan(
      from: origin, on: surface, speed: 30, activity: 1, maxDuration: 5, random: &random),
      plan.reachesEdge
    {
      reachedBoundary = surface.isAtBoundary(plan.target)
      break
    }
  }
  #expect(reachedBoundary)
}

@Test func windowMotionFeedbackClampsLeanAndStretch() {
  let topMove = WindowMotionFeedback(
    edge: .top, horizontalSpeed: 5000, verticalSpeed: 0, widthSpeed: 0, resized: false)
  #expect(topMove.lean == -WindowMotionFeedback.maxLeanAngle)
  #expect(topMove.stretch == 0)
  let sideResize = WindowMotionFeedback(
    edge: .left, horizontalSpeed: 0, verticalSpeed: -4400, widthSpeed: 6000, resized: true)
  #expect(sideResize.lean == WindowMotionFeedback.maxLeanAngle)
  #expect(sideResize.stretch == WindowMotionFeedback.maxStretch)
}

@Test func neighborProximitySupportsMultipleCompanionsAndVerticalEdges() {
  let topPositions = [
    CGPoint(x: 200, y: 500),
    CGPoint(x: 500, y: 500),
    CGPoint(x: 530, y: 500),
  ]
  let topEdges: [PerchSurface.Edge] = [.top, .top, .top]
  #expect(
    NeighborProximity.nearbyIndices(positions: topPositions, edges: topEdges, size: 64) == [1, 2])
  let wallPositions = [
    CGPoint(x: 199, y: 300),
    CGPoint(x: 199, y: 340),
    CGPoint(x: 801, y: 310),
  ]
  let wallEdges: [PerchSurface.Edge] = [.left, .left, .right]
  #expect(
    NeighborProximity.nearbyIndices(positions: wallPositions, edges: wallEdges, size: 64) == [0, 1])
}
