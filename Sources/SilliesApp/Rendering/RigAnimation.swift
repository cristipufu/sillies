import QuartzCore

/// Small, cancellable layer clips shared by built-in and character-specific animations.
@MainActor
enum RigAnimation {
  struct Oscillation {
    let keyPath: String
    let from: Double
    let to: Double
    let duration: Double
  }

  struct Sequence {
    let keyPath: String
    let values: [Double]
    let times: [NSNumber]
    let duration: Double
  }

  static func oscillate(_ layer: CALayer, _ motion: Oscillation) {
    swing(layer, motion.keyPath, from: motion.from, to: motion.to, duration: motion.duration)
  }

  static func play(_ layer: CALayer, _ motion: Sequence) {
    keyframes(
      layer, motion.keyPath, values: motion.values, times: motion.times,
      duration: motion.duration, repeats: false)
  }

  static func loop(_ layer: CALayer, _ motion: Sequence) {
    keyframes(
      layer, motion.keyPath, values: motion.values, times: motion.times,
      duration: motion.duration)
  }

  static func swing(
    _ layer: CALayer, _ key: String, from: Double, to: Double, duration: Double
  ) {
    let animation = CABasicAnimation(keyPath: key)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: key)
  }

  static func keyframes(
    _ layer: CALayer, _ key: String, values: [Double], times: [NSNumber], duration: Double,
    repeats: Bool = true
  ) {
    let animation = CAKeyframeAnimation(keyPath: key)
    animation.values = values
    animation.keyTimes = times
    animation.duration = duration
    animation.repeatCount = repeats ? .infinity : 0
    animation.timingFunctions = (1..<values.count).map { _ in
      CAMediaTimingFunction(name: .easeInEaseOut)
    }
    layer.add(animation, forKey: key)
  }
}
