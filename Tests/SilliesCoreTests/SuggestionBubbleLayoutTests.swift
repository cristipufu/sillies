import Foundation
import SilliesCore
import Testing

@Test func suggestionBubbleFitsScreenAndPointsTowardCompanion() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let size = CGSize(width: 280, height: 100)
  let left = CompanionSpeechBubbleLayout(
    anchor: .init(companionPoint: CGPoint(x: 100, y: 850), characterSize: 70, visibleFrame: screen),
    size: size)
  let right = CompanionSpeechBubbleLayout(
    anchor: .init(
      companionPoint: CGPoint(x: 1350, y: 850), characterSize: 70, visibleFrame: screen),
    size: size)
  #expect(screen.contains(left.frame) && screen.contains(right.frame))
  #expect(left.tail == .left && right.tail == .right)
  #expect(left.frame.size == size && right.frame.size == size)
  #expect(left.tailOffset >= 32 && right.tailOffset <= size.height - 32)
}

@Test func suggestionBubbleClampsMeasuredSizeToSmallScreens() {
  let screen = CGRect(x: -320, y: 20, width: 240, height: 180)
  let layout = CompanionSpeechBubbleLayout(
    anchor: .init(
      companionPoint: CGPoint(x: -200, y: 100), characterSize: 64, visibleFrame: screen),
    size: CGSize(width: 300, height: 220))
  #expect(screen.contains(layout.frame))
  #expect(layout.frame.size == CompanionSpeechBubbleLayout.availableSize(in: screen))
  #expect(layout.tailOffset >= 0 && layout.tailOffset <= layout.frame.height)
}

@Test(arguments: [56.0, 84.0, 120.0])
func talkBubbleLeavesClearanceAboveTheWindowContact(characterSize: Double) {
  let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
  let point = CGPoint(x: 400, y: 400)
  let layout = CompanionSpeechBubbleLayout(
    anchor: .init(companionPoint: point, characterSize: characterSize, visibleFrame: screen),
    size: CGSize(width: 266, height: 65), placement: .aboveContact)
  #expect(layout.frame.minY >= point.y + CompanionSpeechBubbleLayout.contactClearance)
  #expect(screen.contains(layout.frame))
  #expect(layout.tail == .left && layout.tailOffset > 0)
}

@Test func meetingThoughtChoosesFreeSpaceWithoutCoveringRecordingControls() throws {
  let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
  for point in [CGPoint(x: 600, y: 400), CGPoint(x: 50, y: 400), CGPoint(x: 1150, y: 870)] {
    let anchor = CompanionSpeechBubbleLayout.Anchor(
      companionPoint: point, characterSize: 84, visibleFrame: screen)
    let controls = CompanionSpeechBubbleLayout(
      anchor: anchor, size: CGSize(width: 340, height: 64), placement: .aboveContact)
    let thought = try #require(
      CompanionSpeechBubbleLayout(
        anchor: anchor, size: CGSize(width: 280, height: 100), avoiding: controls.frame))
    #expect(screen.contains(thought.frame))
    #expect(!thought.frame.intersects(controls.frame))
    if point.x == 600 { #expect(thought.tail != controls.tail) }
  }
}

@Test func meetingThoughtYieldsWhenControlsLeaveNoRoom() {
  let screen = CGRect(x: -320, y: 20, width: 240, height: 180)
  let anchor = CompanionSpeechBubbleLayout.Anchor(
    companionPoint: CGPoint(x: -200, y: 100), characterSize: 64, visibleFrame: screen)
  let controls = CompanionSpeechBubbleLayout(
    anchor: anchor, size: CGSize(width: 340, height: 64), placement: .aboveContact)
  #expect(
    CompanionSpeechBubbleLayout(
      anchor: anchor, size: CGSize(width: 280, height: 120), avoiding: controls.frame) == nil)
}

@Test func raisedTalkBubbleStaysOnscreenWhenHeadroomIsLimited() {
  let screen = CGRect(x: -900, y: 30, width: 900, height: 600)
  let layout = CompanionSpeechBubbleLayout(
    anchor: .init(
      companionPoint: CGPoint(x: -100, y: screen.maxY), characterSize: 84, visibleFrame: screen),
    size: CGSize(width: 266, height: 65), placement: .aboveContact)
  #expect(screen.contains(layout.frame))
  #expect(layout.tail == .right)
  #expect(layout.tailOffset >= 0 && layout.tailOffset <= layout.frame.height)
}

@Test func talkBubbleChoosesTheInwardSideAtBothHostWindowCorners() {
  let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
  let window = CGRect(x: 500, y: 250, width: 600, height: 400)
  for (position, expectedTail) in [
    (window.minX + 8, CompanionSpeechBubbleLayout.Tail.left),
    (window.maxX - 8, .right),
  ] {
    let layout = CompanionSpeechBubbleLayout(
      anchor: .init(
        companionPoint: CGPoint(x: position, y: window.maxY), characterSize: 84,
        visibleFrame: screen, windowFrame: window),
      size: CGSize(width: 266, height: 65), placement: .aboveContact)
    #expect(layout.tail == expectedTail)
    #expect(layout.frame.minX >= window.minX && layout.frame.maxX <= window.maxX)
    #expect(layout.frame.minY >= window.maxY + CompanionSpeechBubbleLayout.contactClearance)
  }
}

@Test func talkBubbleFallsBackToScreenBoundsForAnUndersizedOrOffscreenHost() {
  let screen = CGRect(x: -1200, y: 0, width: 1200, height: 900)
  for window in [
    CGRect(x: -900, y: 100, width: 180, height: 400),
    CGRect(x: -100, y: 100, width: 800, height: 400),
  ] {
    let layout = CompanionSpeechBubbleLayout(
      anchor: .init(
        companionPoint: CGPoint(x: window.minX, y: window.maxY), characterSize: 84,
        visibleFrame: screen, windowFrame: window),
      size: CGSize(width: 266, height: 65), placement: .aboveContact)
    #expect(screen.contains(layout.frame))
    #expect(layout.frame.width == 266)
  }
}
