import Foundation
import SilliesCore
import Testing

@Test func movingAWindowPreservesDistinctCompanionSlots() {
  let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let window = CGRect(x: 100, y: 100, width: 800, height: 500)
  let original = PerchSurface(window: window, visibleFrame: display, characterSize: 64)
  let destination = PerchSurface(
    window: window.offsetBy(dx: 70, dy: 10), visibleFrame: display, characterSize: 64)
  for fraction in [0.2, 0.5, 0.8] {
    let change = PerchAttachmentChange(
      previous: .init(
        surface: original, windowID: 1, position: original.point(at: fraction), heldFraction: nil),
      surface: destination, windowID: 1, fallbackFraction: 0.5)
    #expect(change.transition == .moved)
    #expect(!change.needsArrangement)
    #expect(abs(destination.fraction(for: change.target) - fraction) < 0.001)
  }
}

@Test func returningCompanionUsesItsPickupSlotWhenTheWindowChanges() {
  let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let surface = PerchSurface(
    window: CGRect(x: 100, y: 100, width: 800, height: 500), visibleFrame: display,
    characterSize: 64)
  let change = PerchAttachmentChange(
    previous: .init(
      surface: surface, windowID: 1, position: CGPoint(x: 1200, y: 800), heldFraction: 0.2),
    surface: surface, windowID: 2, fallbackFraction: 0.5)
  #expect(change.transition == .reattached)
  #expect(change.needsArrangement)
  #expect(change.target == surface.point(at: 0.2))
}

@Test func minimizingTransitionSurvivesAppSwitchWithoutAcceptingAnUnstableCandidate() {
  var transition = WindowTransitionState()
  let frame = CGRect(x: 100, y: 100, width: 800, height: 500)
  transition.begin(originWindowID: 1, reason: .minimize, at: 1)
  transition.observeCandidate(windowID: 2, frame: frame, at: 2)
  transition.observeCandidate(windowID: 2, frame: frame.offsetBy(dx: 6, dy: 0), at: 3)
  #expect(transition.candidateStableSince == 2)
  transition.preserveAcrossApplicationSwitch(at: 4)
  #expect(transition.isActive && transition.originWindowID == 1)
  #expect(transition.candidateWindowID == nil)
  transition.observeCandidate(windowID: 3, frame: frame, at: 5)
  #expect(transition.candidateStableSince == 5)
  transition.reset()
  transition.begin(originWindowID: 3, reason: .geometry, at: 6)
  transition.preserveAcrossApplicationSwitch(at: 7)
  #expect(!transition.isActive)
}
