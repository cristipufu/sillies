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

@Test func sideConversationTailsFaceTheMascotAndPreserveContentDimensions() {
  let display = CGRect(x: -1400, y: -900, width: 1400, height: 900)
  let body = CGSize(width: 400, height: 548)
  for edge in [PerchSurface.Edge.left, .right] {
    let point = CGPoint(x: edge == .left ? -1200 : -200, y: -450)
    let size = ConversationBubbleLayout.windowSize(forBody: body, edge: edge)
    let layout = ConversationBubbleLayout(
      anchor: point, size: size, visibleFrame: display, edge: edge)
    #expect(layout.tail == (edge == .left ? .left : .right))
    #expect(display.contains(layout.frame))
    #expect(layout.frame.width - ConversationBubbleLayout.tailHeight == body.width)
    #expect(layout.frame.height == body.height)
    #expect(layout.frame.maxY - layout.tailOffset == point.y)
    #expect((edge == .left ? layout.frame.minX : layout.frame.maxX) == point.x)
  }
}

@Test func resizingOrMovingAHostToTheTopSelectsASideTail() {
  let display = CGRect(x: 0, y: 0, width: 1400, height: 900)
  let normal = CGRect(x: 200, y: 100, width: 800, height: 400)
  let tall = CGRect(x: normal.minX, y: normal.minY, width: normal.width, height: 800)
  let moved = normal.offsetBy(dx: 0, dy: 420)
  for preferRight in [false, true] {
    for frame in [tall, moved] {
      let surface = PerchSurface(
        window: frame, visibleFrame: display, characterSize: 64, preferRight: preferRight)
      #expect(surface.edge == (preferRight ? .right : .left))
      let size = ConversationBubbleLayout.windowSize(
        forBody: CGSize(width: 400, height: 548), edge: surface.edge)
      let anchor = surface.point(at: 0.5)
      let layout = ConversationBubbleLayout(
        anchor: anchor, size: size, visibleFrame: display, edge: surface.edge)
      #expect(layout.tail == (preferRight ? .right : .left))
      #expect(display.contains(layout.frame))
      #expect(layout.frame.maxY - layout.tailOffset == anchor.y)
    }
  }
}

@Test(arguments: [ConversationBubbleLayout.Tail.top, .bottom, .left, .right])
func conversationOutlineHasATailOnlyOnItsSelectedEdge(_ tail: ConversationBubbleLayout.Tail) throws
{
  let bounds = CGRect(x: 0, y: 0, width: 400, height: 560)
  let path = ConversationBubbleOutline(tail: tail, offset: 200).path(in: bounds)
  let tips: [(ConversationBubbleLayout.Tail, CGPoint)] = [
    (.top, CGPoint(x: 200, y: 6)), (.bottom, CGPoint(x: 200, y: 554)),
    (.left, CGPoint(x: 6, y: 200)), (.right, CGPoint(x: 394, y: 200)),
  ]
  let selected = try #require(tips.first { $0.0 == tail })
  #expect(path.contains(selected.1))
  let gap = tail.isSide ? CGPoint(x: selected.1.x, y: 230) : CGPoint(x: 230, y: selected.1.y)
  #expect(!path.contains(gap))
  #expect(path.contains(CGPoint(x: bounds.midX, y: bounds.midY)))
  #expect(!path.contains(CGPoint(x: 1, y: 1)))
}

@Test func bubbleOutlineWaitsForUsableNativeBounds() {
  let outline = ConversationBubbleOutline(tail: .left, offset: 100, inset: 0.5)
  for bounds in [CGRect.zero, CGRect(x: 0, y: 0, width: 1, height: 1), .null, .infinite] {
    #expect(outline.path(in: bounds).isEmpty)
  }
}
