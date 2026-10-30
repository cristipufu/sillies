import Foundation

public struct WindowTransitionObservation: Sendable {
  public struct Window: Sendable {
    public let id: UInt32
    public let frame: CGRect
    public init?(id: UInt32?, frame: CGRect?) {
      guard let id, let frame else { return nil }
      self.id = id
      self.frame = frame
    }
  }
  public struct Visibility: Sendable {
    public let currentFrames: [Int: CGRect]
    public let priorFrames: [Int: CGRect]
    public let verifiedStandardFrames: [CGRect]?
    public init(
      currentFrames: [Int: CGRect], priorFrames: [Int: CGRect], verifiedStandardFrames: [CGRect]?
    ) {
      self.currentFrames = currentFrames
      self.priorFrames = priorFrames
      self.verifiedStandardFrames = verifiedStandardFrames
    }
    func excludes(_ frame: CGRect) -> Bool {
      verifiedStandardFrames.map { frames in
        !frames.contains { WindowFrameComparison.matches($0, frame) }
      } ?? false
    }
  }
  public struct Initiation: Sendable {
    public let originWindowID: UInt32
    public let reason: WindowTransitionState.Reason
    public let candidate: Window?
  }
  public let current: Window?
  public let resolved: Window?
  public let visibility: Visibility

  public init(current: Window?, resolved: Window?, visibility: Visibility) {
    self.current = current
    self.resolved = resolved
    self.visibility = visibility
  }

  public var initiation: Initiation? {
    guard let current else { return newlyAppearingTransition }
    guard let resolved else {
      return visibility.currentFrames[Int(current.id)] != nil || visibility.excludes(current.frame)
        ? Initiation(originWindowID: current.id, reason: .minimize, candidate: nil) : nil
    }
    if resolved.id == current.id {
      return WindowFrameComparison.matches(current.frame, resolved.frame)
        ? nil : Initiation(originWindowID: current.id, reason: .geometry, candidate: resolved)
    }
    guard let originFrame = visibility.currentFrames[Int(current.id)],
      !WindowFrameComparison.matches(current.frame, originFrame)
        || visibility.excludes(current.frame)
    else { return nil }
    return Initiation(originWindowID: current.id, reason: .minimize, candidate: resolved)
  }

  private var newlyAppearingTransition: Initiation? {
    guard let resolved, let prior = visibility.priorFrames[Int(resolved.id)],
      !WindowFrameComparison.matches(prior, resolved.frame)
    else { return nil }
    return Initiation(originWindowID: resolved.id, reason: .geometry, candidate: resolved)
  }
}
