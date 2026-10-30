import Foundation

/// Pure state for a window visibility transition. The platform owns polling and notifications.
public struct WindowTransitionState: Sendable {
  public enum Reason: Sendable { case minimize, geometry }
  public init() {}
  public private(set) var isActive = false
  public private(set) var originWindowID: UInt32?
  public private(set) var isMinimizingOrigin = false
  public private(set) var startedAt: Double = 0
  public private(set) var lastActivityAt: Double = 0
  public private(set) var candidateWindowID: UInt32?
  public private(set) var candidateFrame: CGRect?
  public private(set) var candidateStableSince: Double = 0

  public mutating func begin(
    originWindowID: UInt32?,
    reason: Reason,
    at now: Double
  ) {
    if !isActive {
      isActive = true
      self.originWindowID = originWindowID
      isMinimizingOrigin = reason == .minimize
      startedAt = now
      candidateWindowID = nil
      candidateFrame = nil
      candidateStableSince = now
    } else {
      if reason == .minimize {
        isMinimizingOrigin = true
      }
      if self.originWindowID == nil {
        self.originWindowID = originWindowID
      }
    }
    lastActivityAt = now
  }

  public mutating func recordActivity(reason: Reason = .geometry, at now: Double) {
    guard isActive else { return }
    if reason == .minimize {
      isMinimizingOrigin = true
    }
    lastActivityAt = now
    candidateStableSince = now
  }

  public mutating func observeCandidate(windowID: UInt32, frame: CGRect, at now: Double) {
    if candidateWindowID != windowID
      || candidateFrame.map({ !WindowFrameComparison.matches($0, frame) }) != false
    {
      candidateWindowID = windowID
      candidateFrame = frame
      candidateStableSince = now
    }
  }

  public mutating func clearCandidate(at now: Double) {
    candidateWindowID = nil
    candidateFrame = nil
    candidateStableSince = now
  }

  public mutating func preserveAcrossApplicationSwitch(at now: Double) {
    guard isActive && isMinimizingOrigin else {
      reset()
      return
    }
    clearCandidate(at: now)
  }

  public mutating func reset() {
    self = WindowTransitionState()
  }
}
