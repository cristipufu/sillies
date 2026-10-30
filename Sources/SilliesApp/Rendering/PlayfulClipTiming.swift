import QuartzCore

@MainActor
enum PlayfulClipTiming {
  /// Convert one shared presentation timestamp into each layer's local clock.
  /// Only the behavior subtree is touched; continuous workspace feedback stays independent.
  static func synchronize(_ layer: CALayer, startingAt time: CFTimeInterval) {
    for key in layer.animationKeys() ?? [] {
      guard let animation = layer.animation(forKey: key)?.copy() as? CAAnimation else { continue }
      animation.beginTime = layer.convertTime(time, from: nil)
      layer.add(animation, forKey: key)
    }
    for child in layer.sublayers ?? [] { synchronize(child, startingAt: time) }
  }
}
