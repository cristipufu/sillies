import CoreGraphics
import SilliesCore
import Testing

@Test func windowCoverageRequiresTheWholeWindowToBeCovered() {
  let window = CGRect(x: 0, y: 0, width: 600, height: 400)
  let left = CGRect(x: 0, y: 0, width: 300, height: 400)
  let right = CGRect(x: 300, y: 0, width: 300, height: 400)
  #expect(WindowCoverage.hasVisibleArea(in: window, behind: [left]))
  #expect(!WindowCoverage.hasVisibleArea(in: window, behind: [left, right]))
  #expect(WindowCoverage.hasVisibleArea(in: window, behind: [left, right.offsetBy(dx: 1, dy: 0)]))
  #expect(WindowCoverage.hasVisibleArea(in: window, behind: [window.offsetBy(dx: 600, dy: 0)]))
  #expect(!WindowCoverage.hasVisibleArea(in: window, behind: [window.insetBy(dx: -100, dy: -100)]))
}
