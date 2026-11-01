import Foundation
import SilliesCore
import Testing

@Test func conversationBubbleStaysOnScreenAndTailTracksMascot() {
  let display = CGRect(x: -1280, y: 0, width: 1280, height: 800)
  for point in [CGPoint(x: -1270, y: 780), CGPoint(x: -20, y: 790), CGPoint(x: -600, y: 40)] {
    let layout = ConversationBubbleLayout(
      anchor: point, size: CGSize(width: 400, height: 560), visibleFrame: display)
    #expect(display.contains(layout.frame))
    #expect(layout.tailOffset >= 0 && layout.tailOffset <= layout.frame.width)
    #expect(layout.tail == (point.y < 100 ? .bottom : .top))
  }
}
