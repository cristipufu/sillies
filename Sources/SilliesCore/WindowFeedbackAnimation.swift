import Foundation

/// Analytical samples let an interrupted inertia clip continue without render-tree readback.
public struct WindowFeedbackAnimation: Sendable {
  public enum Style: Sendable {
    case following
    case settling
  }

  public static let followDuration: TimeInterval = 0.09
  public static let settleDuration: TimeInterval = 0.55
  public static let springMass: Double = 0.7
  public static let springStiffness: Double = 200
  public static let springDamping: Double = 12

  public let start: WindowMotionFeedback
  public let end: WindowMotionFeedback
  public let startedAt: TimeInterval
  public let style: Style

  public var duration: TimeInterval {
    style == .following ? Self.followDuration : Self.settleDuration
  }

  public init(
    from start: WindowMotionFeedback, to end: WindowMotionFeedback,
    at time: TimeInterval, style: Style
  ) {
    self.start = start
    self.end = end
    startedAt = time
    self.style = style
  }

  public func value(at time: TimeInterval) -> WindowMotionFeedback {
    let elapsed = max(0, time - startedAt)
    guard elapsed < duration else { return end }
    let progress = style == .following ? elapsed / duration : springProgress(at: elapsed)
    return WindowMotionFeedback(
      lean: start.lean + (end.lean - start.lean) * progress,
      stretch: start.stretch + (end.stretch - start.stretch) * progress)
  }

  private func springProgress(at elapsed: TimeInterval) -> Double {
    let decay = Self.springDamping / (2 * Self.springMass)
    let frequency = sqrt(Self.springStiffness / Self.springMass - decay * decay)
    let oscillation = cos(frequency * elapsed) + decay / frequency * sin(frequency * elapsed)
    return 1 - exp(-decay * elapsed) * oscillation
  }
}
