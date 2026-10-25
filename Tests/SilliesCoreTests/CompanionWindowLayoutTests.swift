import CoreGraphics
import Testing

@testable import SilliesCore

@Test func nativePanelBoundsExcludeTheFocusedWindowOnEveryEdge() {
  let window = CGRect(x: 200, y: 200, width: 800, height: 500)
  let cases: [(PerchSurface.Edge, CGPoint)] = [
    (.top, CGPoint(x: 450, y: 701)), (.left, CGPoint(x: 199, y: 450)),
    (.right, CGPoint(x: 1001, y: 450)),
  ]
  for (edge, contact) in cases {
    let layout = CompanionWindowLayout(contact: contact, size: 64, window: window, edge: edge)
    #expect(layout.frame.intersection(window).isEmpty)
    #expect(abs(layout.frame.minX + layout.contactOffset.x - contact.x) < 0.0001)
    #expect(abs(layout.frame.minY + layout.contactOffset.y - contact.y) < 0.0001)
    #expect(layout.frame.width * layout.frame.height < pow(256 * 0.64, 2) * 0.6)
  }
}

@Test func detachedPickupKeepsTheFullCanvasAndExactContact() {
  let point = CGPoint(x: 500, y: 600)
  let layout = CompanionWindowLayout(contact: point, size: 64, window: nil, edge: .top)
  #expect(abs(layout.frame.width - 163.84) < 0.0001)
  #expect(abs(layout.frame.midX - point.x) < 0.0001)
  #expect(abs(layout.frame.midY - point.y) < 0.0001)
}

@Test func returningFromInsideTheDocumentNeverCreatesAnInputWindowOverIt() {
  let window = CGRect(x: 200, y: 200, width: 800, height: 500)
  let layout = CompanionWindowLayout(
    contact: CGPoint(x: 400, y: 300), size: 64, window: window, edge: .top)
  #expect(layout.frame.minY >= window.maxY)
  #expect(layout.frame.intersection(window).isEmpty)
}
