import QuartzCore
import Testing

@testable import SilliesApp

@Test @MainActor
func hitTestingProtectsDecorationsAndUpdatesChangingStrokeGeometry() {
  let canvas = CALayer()
  let artwork = CALayer()
  artwork.name = ArtworkHitTester.interactiveRootName
  canvas.addSublayer(artwork)
  let stroke = CAShapeLayer()
  stroke.fillColor = nil
  stroke.strokeColor = CGColor(gray: 0, alpha: 1)
  stroke.lineWidth = 2
  let firstPath = CGMutablePath()
  firstPath.move(to: .zero)
  firstPath.addLine(to: CGPoint(x: 20, y: 0))
  stroke.path = firstPath
  artwork.addSublayer(stroke)
  let decoration = CAShapeLayer()
  decoration.name = ArtworkHitTester.decorationName
  decoration.path = CGPath(rect: CGRect(x: 60, y: 60, width: 20, height: 20), transform: nil)
  artwork.addSublayer(decoration)

  let tester = ArtworkHitTester()
  #expect(tester.containsArtwork(in: canvas, at: CGPoint(x: 10, y: 2)))
  #expect(!tester.containsArtwork(in: canvas, at: CGPoint(x: 70, y: 70)))
  #expect(!tester.containsArtwork(in: canvas, at: CGPoint(x: 40, y: 40)))
  stroke.path = CGPath(rect: CGRect(x: 40, y: 40, width: 10, height: 10), transform: nil)
  #expect(!tester.containsArtwork(in: canvas, at: CGPoint(x: 10, y: 2)))
  #expect(tester.containsArtwork(in: canvas, at: CGPoint(x: 45, y: 40)))
  artwork.opacity = 0
  #expect(!tester.containsArtwork(in: canvas, at: CGPoint(x: 45, y: 40)))
}
