import Foundation
import SilliesCore
import Testing

@Test func suggestionBubbleFitsScreenAndPointsTowardCompanion() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let left = SuggestionBubbleLayout(
    companionPoint: CGPoint(x: 100, y: 850), characterSize: 70, visibleFrame: screen)
  let right = SuggestionBubbleLayout(
    companionPoint: CGPoint(x: 1350, y: 850), characterSize: 70, visibleFrame: screen)
  #expect(screen.contains(left.frame) && screen.contains(right.frame))
  #expect(left.tail == .left && right.tail == .right)
  #expect(left.tailOffset >= 32 && right.tailOffset <= SuggestionBubbleLayout.size.height - 32)
}
