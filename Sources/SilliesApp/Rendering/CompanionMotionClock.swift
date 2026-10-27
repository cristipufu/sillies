import AppKit
import QuartzCore

/// One display-linked clock for the crew's travel and deliberate pickup gestures.
/// A screen link keeps offscreen return tweens advancing even while their panels are clipped.
@MainActor
final class CompanionMotionClock: NSObject {
  enum Cadence {
    private static let lowPowerMotionFPS: Float = 30
    private static let lowPowerInteractionFPS: Float = 60

    case display
    case lowPowerMotion
    case lowPowerInteraction

    func maximumFramesPerSecond(on screen: NSScreen) -> Float {
      let maximum = Float(screen.maximumFramesPerSecond)
      switch self {
      case .display: return maximum
      case .lowPowerMotion: return min(maximum, Self.lowPowerMotionFPS)
      case .lowPowerInteraction: return min(maximum, Self.lowPowerInteractionFPS)
      }
    }
  }

  var onFrame: ((TimeInterval) -> Void)?
  private var link: CADisplayLink?
  private var screenNumber: NSNumber?
  private var frameRate: Float = 0
  var isRunning: Bool { link != nil }

  func configure(screen: NSScreen?, cadence: Cadence) {
    guard let screen else {
      stop()
      return
    }
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let maximum = cadence.maximumFramesPerSecond(on: screen)
    guard link == nil || screenNumber != number || frameRate != maximum else { return }
    stop()
    screenNumber = number
    frameRate = maximum
    let created = screen.displayLink(target: self, selector: #selector(displayFrame(_:)))
    created.preferredFrameRateRange = CAFrameRateRange(
      minimum: maximum, maximum: maximum, preferred: maximum)
    created.add(to: .main, forMode: .common)
    link = created
  }

  func stop() {
    link?.invalidate()
    link = nil
    screenNumber = nil
    frameRate = 0
  }

  @objc private func displayFrame(_ link: CADisplayLink) {
    // Translate the presentation deadline into the uptime domain used by MotionTween.
    let lead = max(0, link.targetTimestamp - CACurrentMediaTime())
    onFrame?(ProcessInfo.processInfo.systemUptime + lead)
  }
}
