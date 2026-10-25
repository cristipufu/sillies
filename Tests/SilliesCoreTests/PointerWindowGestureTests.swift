import CoreGraphics
import Testing

@testable import SilliesCore

@Test func sidePosesAttachByRaisedHandsInsteadOfRotatingFeetToTheWall() {
  #expect(AttachmentPose.hangingLeft.isHanging)
  #expect(AttachmentPose.hangingRight.isHanging)
  #expect(AttachmentPose.hangingLeft.anchor.y > AttachmentPose.standing.anchor.y + 60)
  #expect(AttachmentPose.hangingLeft.anchor.x + AttachmentPose.hangingRight.anchor.x == 128)
  let window = CGRect(x: 160, y: 80, width: 1000, height: 850)
  let display = CGRect(x: 0, y: 40, width: 1400, height: 900)
  let left = PerchSurface(window: window, visibleFrame: display, characterSize: 64)
  let right = PerchSurface(
    window: window, visibleFrame: display, characterSize: 64, preferRight: true)
  #expect(left.attachmentPose == .hangingLeft)
  #expect(right.attachmentPose == .hangingRight)
  #expect(left.start.y - (AttachmentPose.hangingLeft.anchor.y - 20) * 0.64 >= display.minY)
}

@Test func pointerDragHasNoFilteringOrAccumulatedReversalLag() throws {
  let frame = CGRect(x: 100, y: 200, width: 700, height: 500)
  let gesture = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: 350, y: 680), at: 0))
  for index in 0..<500 {
    let dx = Double(index.isMultiple(of: 2) ? 150 : -150)
    let result = gesture.frame(at: CGPoint(x: 350 + dx, y: 710))
    #expect(result == frame.offsetBy(dx: dx, dy: 30))
  }
}

@Test func pointerResizeTracksEachEdgeAndCornerImmediately() throws {
  let frame = CGRect(x: 100, y: 200, width: 700, height: 500)
  let rightBottom = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: 800, y: 200), at: 0))
  #expect(
    rightBottom.frame(at: CGPoint(x: 920, y: 160))
      == CGRect(x: 100, y: 160, width: 820, height: 540))
  let leftTop = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: 100, y: 700), at: 0))
  #expect(
    leftTop.frame(at: CGPoint(x: 70, y: 780)) == CGRect(x: 70, y: 200, width: 730, height: 580))
}

@Test func gestureRejectsDocumentDragsAndBoundsMinimumResize() throws {
  let frame = CGRect(x: 100, y: 200, width: 700, height: 500)
  #expect(PointerWindowGesture(frame: frame, pointer: CGPoint(x: 350, y: 400), at: 0) == nil)
  let left = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: 100, y: 450), at: 0))
  #expect(left.frame(at: CGPoint(x: 900, y: 450)).width == 120)
  #expect(left.frame(at: CGPoint(x: 900, y: 450)).maxX == 800)
}

@Test func oldMetadataValidatesButDoesNotPullNewPointerPositionBack() throws {
  let frame = CGRect(x: -900, y: 1200, width: 700, height: 500)
  let gesture = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: -600, y: 1680), at: 0))
  let points = [CGPoint(x: -580, y: 1680), CGPoint(x: -540, y: 1680), CGPoint(x: -500, y: 1680)]
  #expect(gesture.matches(frame.offsetBy(dx: 20, dy: 0), recentPointers: points))
  #expect(gesture.frame(at: points[2]).minX == -800)
  #expect(!gesture.matches(CGRect(x: 0, y: 0, width: 1400, height: 900), recentPointers: points))
}

@Test func optionResizeKeepsWindowCenterFixed() throws {
  let frame = CGRect(x: 100, y: 200, width: 700, height: 500)
  let gesture = try #require(
    PointerWindowGesture(frame: frame, pointer: CGPoint(x: 800, y: 450), at: 0, centered: true))
  let resized = gesture.frame(at: CGPoint(x: 850, y: 450))
  #expect(resized.width == 800)
  #expect(resized.midX == frame.midX)
}
