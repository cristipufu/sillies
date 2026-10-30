import QuartzCore

/// Freeze only exported clip animations at their scene time so PNG encoding cannot distort motion.
@MainActor
final class PlayfulPreviewClock {
  private var phaseIndex: Int?
  private var offsets: [ObjectIdentifier: [String: Double]] = [:]

  func sample(_ layers: [CALayer], phase: Int, elapsed: Double) {
    if phaseIndex != phase {
      phaseIndex = phase
      offsets.removeAll(keepingCapacity: true)
    }
    for layer in layers { sample(layer, elapsed: elapsed) }
    CATransaction.flush()
  }

  private func sample(_ layer: CALayer, elapsed: Double) {
    let identity = ObjectIdentifier(layer)
    for key in layer.animationKeys() ?? [] {
      guard let animation = layer.animation(forKey: key)?.copy() as? CAAnimation else { continue }
      let offset = offsets[identity]?[key] ?? animation.timeOffset
      offsets[identity, default: [:]][key] = offset
      animation.speed = 0
      animation.beginTime = 0
      animation.timeOffset = elapsed + offset
      animation.fillMode = .both
      animation.isRemovedOnCompletion = false
      layer.add(animation, forKey: key)
    }
    for child in layer.sublayers ?? [] { sample(child, elapsed: elapsed) }
  }
}
