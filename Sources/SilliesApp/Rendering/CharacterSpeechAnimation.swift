import AppKit
import QuartzCore

/// Playback drives a small native layer transition, never a timer or a SwiftUI animation loop.
@MainActor final class CharacterSpeechAnimation {
  private static let transitionDuration: TimeInterval = 0.10
  private static let maximumHeadLift = 1.2
  private static let maximumMouthWidth: CGFloat = 10
  private static let mouthHeight: CGFloat = 6
  private let head: CALayer
  private var restingMouth: CAShapeLayer?
  private var openMouth: CAShapeLayer?
  private var level = 0.0

  init(head: CALayer) { self.head = head }

  func registerMouth(_ mouth: CAShapeLayer) {
    guard let path = mouth.path else { return }
    restingMouth = mouth
    let bounds = path.boundingBoxOfPath
    let width = min(Self.maximumMouthWidth, max(4, bounds.width * 0.6))
    let speaking = CAShapeLayer()
    speaking.bounds = CGRect(x: 0, y: 0, width: width, height: Self.mouthHeight)
    speaking.position = CGPoint(x: bounds.midX, y: bounds.midY)
    speaking.path = CGPath(ellipseIn: speaking.bounds, transform: nil)
    speaking.fillColor = mouth.strokeColor ?? mouth.fillColor
    speaking.opacity = 0
    mouth.superlayer?.addSublayer(speaking)
    openMouth = speaking
  }

  func update(level requested: Double) {
    let next = requested.isFinite ? max(0, min(1, requested)) : 0
    guard abs(level - next) > 0.01 || next == 0 && level != 0 else { return }
    let previous = level
    level = next
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    restingMouth?.opacity = next > 0 ? 0 : 1
    openMouth?.opacity = next > 0 ? 1 : 0
    openMouth?.transform = CATransform3DMakeScale(1, max(0.1, next), 1)
    CATransaction.commit()
    if let openMouth {
      interpolate(openMouth, key: "transform.scale.y", from: max(0.1, previous), to: max(0.1, next))
    }
    let nod = CABasicAnimation(keyPath: "transform.translation.y")
    nod.fromValue = previous * Self.maximumHeadLift
    nod.toValue = next * Self.maximumHeadLift
    nod.duration = Self.transitionDuration
    nod.isAdditive = true
    nod.fillMode = .forwards
    nod.isRemovedOnCompletion = false
    nod.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    head.add(nod, forKey: "speech.nod")
  }

  private func interpolate(_ layer: CALayer, key: String, from: Double, to: Double) {
    let animation = CABasicAnimation(keyPath: key)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = Self.transitionDuration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "speech.mouth")
  }
}
