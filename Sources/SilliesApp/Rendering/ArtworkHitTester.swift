import QuartzCore

/// One presentation snapshot per hit test; named roots keep decorations out of cloned trees too.
@MainActor
final class ArtworkHitTester {
  static let interactiveRootName = "sillies.interactiveArtwork"
  static let decorationName = "sillies.decoration"
  private static let minimumVisibleOpacity: Float = 0.1
  private static let minimumStrokeHitWidth: CGFloat = 6
  private static let maximumCachedStrokes = 128

  private struct StrokeKey: Hashable {
    let path: CGPath
    let width: CGFloat
    let miterLimit: CGFloat
  }

  private var strokes: [StrokeKey: CGPath] = [:]

  func containsArtwork(in canvas: CALayer, at point: CGPoint) -> Bool {
    contains(canvas.presentation() ?? canvas, at: point, region: .decoration)
  }

  private enum Region { case decoration, artwork }

  private func contains(_ layer: CALayer, at point: CGPoint, region: Region) -> Bool {
    guard !layer.isHidden, layer.opacity > Self.minimumVisibleOpacity,
      layer.name != Self.decorationName
    else { return false }
    let region = layer.name == Self.interactiveRootName ? Region.artwork : region
    if region == .artwork, let shape = layer as? CAShapeLayer, contains(shape, at: point) {
      return true
    }
    return layer.sublayers?.contains { child in
      contains(child, at: child.convert(point, from: layer), region: region)
    } ?? false
  }

  private func contains(_ shape: CAShapeLayer, at point: CGPoint) -> Bool {
    guard let path = shape.path else { return false }
    if let fill = shape.fillColor, fill.alpha > CGFloat(Self.minimumVisibleOpacity),
      path.contains(point)
    {
      return true
    }
    guard let stroke = shape.strokeColor, stroke.alpha > CGFloat(Self.minimumVisibleOpacity),
      shape.lineWidth > 0
    else { return false }
    let width = max(shape.lineWidth, Self.minimumStrokeHitWidth)
    let halfWidth = width / 2
    guard path.boundingBoxOfPath.insetBy(dx: -halfWidth, dy: -halfWidth).contains(point) else {
      return false
    }
    let key = StrokeKey(path: path, width: width, miterLimit: shape.miterLimit)
    if let cached = strokes[key] { return cached.contains(point) }
    let stroked = path.copy(
      strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: shape.miterLimit)
    if strokes.count >= Self.maximumCachedStrokes { strokes.removeAll(keepingCapacity: true) }
    strokes[key] = stroked
    return stroked.contains(point)
  }
}
