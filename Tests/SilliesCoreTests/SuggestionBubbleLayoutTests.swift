import Foundation
import SilliesCore
import Testing

@Test func suggestionBubbleFitsScreenAndPointsTowardCompanion() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let size = CGSize(width: 280, height: 100)
  let left = SuggestionBubbleLayout(
    anchor: .init(companionPoint: CGPoint(x: 100, y: 850), characterSize: 70, visibleFrame: screen),
    size: size)
  let right = SuggestionBubbleLayout(
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
  let layout = SuggestionBubbleLayout(
    anchor: .init(
      companionPoint: CGPoint(x: -200, y: 100), characterSize: 64, visibleFrame: screen),
    size: CGSize(width: 300, height: 220))
  #expect(screen.contains(layout.frame))
  #expect(layout.frame.size == SuggestionBubbleLayout.availableSize(in: screen))
  #expect(layout.tailOffset >= 0 && layout.tailOffset <= layout.frame.height)
}
