import Foundation
import Testing

@testable import SilliesCore

@Test func outsideClickWaitsForReleaseAndNeverClosesAfterADrag() {
  var dismissal = OutsideClickDismissal()
  let point = CGPoint(x: 200, y: 400)
  let withoutPress = dismissal.release(at: point, button: 0)
  #expect(!withoutPress)
  dismissal.begin(at: point, button: 0)
  let wrongButton = dismissal.release(at: point, button: 1)
  let click = dismissal.release(at: point, button: 0)
  let repeated = dismissal.release(at: point, button: 0)
  #expect(!wrongButton && click && !repeated)

  // A host drag can return to its starting position before release.
  dismissal.begin(at: point, button: 0)
  dismissal.cancel()
  let draggedBack = dismissal.release(at: point, button: 0)
  #expect(!draggedBack)

  // Also preserve the bubble if native tracking coalesced the drag events.
  dismissal.begin(at: point, button: 0)
  let moved = dismissal.release(at: CGPoint(x: 240, y: 400), button: 0)
  #expect(!moved)
  dismissal.begin(at: point, button: 1)
  let rightClick = dismissal.release(at: CGPoint(x: 201, y: 400), button: 1)
  #expect(rightClick)
}
