import Foundation
import SilliesCore
import Testing

@Test func emptyRadialMenusHaveNoTargetsIncludingInvalidNegativeCounts() {
  for count in [0, -1, Int.min] {
    let arc = RadialMenuArc(count: count)
    #expect(arc.radius.isFinite)
    #expect(arc.centers(around: .zero, facingDegrees: 90).isEmpty)
  }
}

@Test func companionActionsOrbitTheMascotAndStayInsideDisplayEdges() {
  let screen = CGRect(x: -1400, y: -400, width: 1400, height: 900)
  let itemSize = CGSize(width: 110, height: 100)
  for x in [screen.minX + 30, screen.midX, screen.maxX - 30] {
    for y in [screen.minY + 30, screen.midY, screen.maxY - 30] {
      let anchor = CGPoint(x: x, y: y)
      let layout = CompanionActionMenuLayout(
        anchor: anchor, count: 4, itemSize: itemSize, visibleFrame: screen)
      #expect(layout.anchor == anchor)
      #expect(layout.centers.count == 4)
      for (index, center) in layout.centers.enumerated() {
        let frame = CGRect(
          x: center.x - itemSize.width / 2, y: center.y - itemSize.height / 2,
          width: itemSize.width, height: itemSize.height)
        #expect(screen.contains(frame))
        #expect(abs(hypot(center.x - anchor.x, center.y - anchor.y) - layout.radius) < 0.001)
        for other in layout.centers.dropFirst(index + 1) {
          #expect(
            hypot(center.x - other.x, center.y - other.y)
              > RadialSkillMenuLayout.bubbleHitRadius * 2)
        }
      }
    }
  }
}

@Test func radialMenuTransparentGapsAndCornersPassInputThrough() {
  let region = RadialMenuItemLayout(center: .zero, titleWidth: 96)
  #expect(region.contains(CGPoint(x: 0, y: 12.5)))
  #expect(region.contains(CGPoint(x: 40, y: -26.5)))
  #expect(!region.contains(CGPoint(x: 24, y: 36)))
  #expect(!region.contains(CGPoint(x: 0, y: -14)))
  #expect(!region.contains(CGPoint(x: 48, y: -17)))
  #expect(!region.contains(CGPoint(x: 80, y: 0)))
}

@Test func conversationControlsBelongInTheBubbleWhileRecordingKeepsItsHUD() {
  let chat = CompanionBindingState.active(target: nil, skill: .chat, startedAt: 0)
  #expect(chat.hasPresentation)
  #expect(!chat.showsTaskHUD)
  #expect(CompanionBindingState.active(target: nil, skill: .record, startedAt: 0).showsTaskHUD)
  #expect(!CompanionBindingState.followingFocusedWindow.showsTaskHUD)
}
