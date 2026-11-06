import QuartzCore
import Testing

/// Samples authored numeric layer curves for headless artwork exports, not timing measurements.
/// Restores the model tree after each sample; it never relies on a live WindowServer presentation.
@MainActor
final class OffscreenClipSampler {
  private struct LayerState {
    let layer: CALayer
    let transform: CATransform3D
    let opacity: Float
    let curves: [Curve]
  }

  private struct Curve {
    let animation: CAPropertyAnimation
    let keyPath: String
    let values: [Double]
    let times: [Double]
    let timing: [CAMediaTimingFunction]

    func value(at elapsed: Double) -> Double? {
      let duration = animation.duration
      let cycle = animation.autoreverses ? duration * 2 : duration
      guard elapsed < cycle || animation.repeatCount > 0 else { return nil }
      let offset = elapsed.truncatingRemainder(dividingBy: cycle)
      let progress = offset > duration ? 2 - offset / duration : offset / duration
      guard let upper = times.indices.dropFirst().first(where: { times[$0] >= progress }) else {
        return values.last
      }
      let lower = upper - 1
      let fraction = (progress - times[lower]) / (times[upper] - times[lower])
      let amount = Self.eased(fraction, by: timing[lower])
      return values[lower] + (values[upper] - values[lower]) * amount
    }

    private static func eased(_ fraction: Double, by timing: CAMediaTimingFunction) -> Double {
      var first: [Float] = [0, 0]
      var second: [Float] = [0, 0]
      timing.getControlPoint(at: 1, values: &first)
      timing.getControlPoint(at: 2, values: &second)
      func coordinate(_ time: Double, _ first: Float, _ second: Float) -> Double {
        let inverse = 1 - time
        return 3 * inverse * inverse * time * Double(first) + 3 * inverse * time * time
          * Double(second) + time * time * time
      }
      var lower = 0.0
      var upper = 1.0
      let precisionSteps = 16
      for _ in 0..<precisionSteps {
        let midpoint = (lower + upper) / 2
        if coordinate(midpoint, first[0], second[0]) < fraction {
          lower = midpoint
        } else {
          upper = midpoint
        }
      }
      return coordinate((lower + upper) / 2, first[1], second[1])
    }
  }

  private let states: [LayerState]

  init(root: CALayer) throws {
    states = try Self.layers(in: root).map { layer in
      let curves = try (layer.animationKeys() ?? []).map { key in
        let animation = try #require(layer.animation(forKey: key) as? CAPropertyAnimation)
        let keyPath = try #require(animation.keyPath)
        if let basic = animation as? CABasicAnimation {
          return Curve(
            animation: animation, keyPath: keyPath,
            values: [
              try #require(basic.fromValue as? NSNumber).doubleValue,
              try #require(basic.toValue as? NSNumber).doubleValue,
            ],
            times: [0, 1],
            timing: [animation.timingFunction ?? CAMediaTimingFunction(name: .default)])
        }
        let frames = try #require(animation as? CAKeyframeAnimation)
        return Curve(
          animation: animation, keyPath: keyPath,
          values: try #require(frames.values as? [NSNumber]).map(\.doubleValue),
          times: try #require(frames.keyTimes).map(\.doubleValue),
          timing: try #require(frames.timingFunctions))
      }
      return LayerState(
        layer: layer, transform: layer.transform, opacity: layer.opacity, curves: curves)
    }
    for state in states { state.layer.removeAllAnimations() }
  }

  func sample(at elapsed: Double) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    restore()
    for state in states {
      for curve in state.curves {
        if let value = curve.value(at: elapsed) {
          state.layer.setValue(value, forKeyPath: curve.keyPath)
        }
      }
    }
  }

  func restore() {
    for state in states {
      state.layer.transform = state.transform
      state.layer.opacity = state.opacity
    }
  }

  private static func layers(in root: CALayer) -> [CALayer] {
    [root] + (root.sublayers ?? []).flatMap { layers(in: $0) }
  }
}
