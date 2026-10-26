import CoreGraphics
import Testing

@testable import SilliesCore

@Test func releasingAboveFallsToThePickupSlotWithABoundedDuration() {
  let origin = CGPoint(x: 200, y: 500)
  let plan = DropReturnPlan(
    releasedAt: CGPoint(x: 360, y: 720), pickedUpAt: origin, destination: origin,
    selectedSkill: false)
  #expect(plan.style == .fall)
  #expect(plan.destination == origin)
  #expect(plan.duration >= 0.1 && plan.duration <= 0.3)
}

@Test func releasingBelowOrChoosingAnySkillRelocates() {
  let origin = CGPoint(x: 200, y: 500)
  let below = DropReturnPlan(
    releasedAt: CGPoint(x: 260, y: 420), pickedUpAt: origin, destination: origin,
    selectedSkill: false)
  let selectedAbove = DropReturnPlan(
    releasedAt: CGPoint(x: 260, y: 650), pickedUpAt: origin, destination: origin,
    selectedSkill: true)
  #expect(below.style == .relocate)
  #expect(selectedAbove.style == .relocate)
}

@Test func releaseDirectionUsesPickupHeightWhenTheWindowHasMoved() {
  let plan = DropReturnPlan(
    releasedAt: CGPoint(x: 200, y: 600), pickedUpAt: CGPoint(x: 200, y: 500),
    destination: CGPoint(x: 400, y: 700), selectedSkill: false)
  #expect(plan.style == .fall)
  #expect(plan.destination == CGPoint(x: 400, y: 700))
}

@Test func shortAndVeryLongFallsStayFastAndFinite() {
  for release in [CGPoint.zero, CGPoint(x: 9000, y: 9000)] {
    let plan = DropReturnPlan(
      releasedAt: release, pickedUpAt: .zero, destination: .zero, selectedSkill: false)
    #expect(plan.duration.isFinite && plan.duration >= 0.1 && plan.duration <= 0.3)
  }
}

@Test func fallingMotionAcceleratesAndClampsExactlyToThePerch() {
  let tween = MotionTween(
    from: CGPoint(x: 300, y: 700), to: CGPoint(x: 200, y: 500), at: 10, duration: 0.2,
    curve: .accelerating)
  let quarter = tween.position(at: 10.05)
  let halfway = tween.position(at: 10.1)
  #expect(700 - quarter.y < halfway.y - tween.position(at: 10.15).y)
  #expect(abs(halfway.y - 650) < 0.001)
  #expect(tween.position(at: 9) == tween.start)
  #expect(tween.position(at: 11) == tween.end)
}
