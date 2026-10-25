import CoreGraphics
import Testing

@testable import SilliesCore

@Test func backgroundContentDoesNotDisableCompanionPlay() {
  let window = CGRect(x: 0, y: 79, width: 1512, height: 870)
  #expect(!WindowInputRegion.protectsControls(at: CGPoint(x: 507, y: 845), frame: window))
  #expect(!WindowInputRegion.protectsControls(at: CGPoint(x: 974, y: 845), frame: window))
}

@Test func customHeaderAndResizeBordersKeepWindowInputPriority() {
  let window = CGRect(x: 100, y: 200, width: 900, height: 500)
  for point in [
    CGPoint(x: 600, y: 680), CGPoint(x: 600, y: 650),
    CGPoint(x: 99, y: 400), CGPoint(x: 700, y: 199), CGPoint(x: 600, y: 704),
  ] {
    #expect(WindowInputRegion.protectsControls(at: point, frame: window))
  }
}
