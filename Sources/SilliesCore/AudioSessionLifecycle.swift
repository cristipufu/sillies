import Foundation

/// Capture decisions and duration accounting use supplied monotonic timestamps, never a timer.
public struct AudioSessionLifecycle: Sendable {
  public enum Phase: Sendable {
    case idle, preparing, capturing, paused, failed, finishing, finished
  }
  public private(set) var phase: Phase = .idle
  public private(set) var failure: SessionFailure?
  private var finalizationNotice: SessionFailure?
  private var startedAt: TimeInterval?
  private var pausedAt: TimeInterval?
  private var stoppedAt: TimeInterval?
  private var pausedDuration: TimeInterval = 0

  public init() {}
  public var acceptsAudio: Bool { phase == .capturing }
  public var canChangeLanguage: Bool { phase == .capturing || phase == .paused }

  @discardableResult public mutating func beginPreparation() -> Bool {
    guard phase == .idle else { return false }
    phase = .preparing
    return true
  }

  @discardableResult public mutating func beginCapture(at now: TimeInterval) -> Bool {
    guard phase == .preparing else { return false }
    startedAt = now
    phase = .capturing
    return true
  }

  @discardableResult public mutating func pause(at now: TimeInterval) -> Bool {
    guard phase == .capturing else { return false }
    pausedAt = now
    phase = .paused
    return true
  }

  @discardableResult public mutating func resume(at now: TimeInterval) -> Bool {
    guard phase == .paused, let pausedAt else { return false }
    pausedDuration += max(0, now - pausedAt)
    self.pausedAt = nil
    phase = .capturing
    return true
  }

  @discardableResult public mutating func fail(_ failure: SessionFailure, at now: TimeInterval)
    -> Bool
  {
    guard phase != .failed, phase != .finishing, phase != .finished else { return false }
    self.failure = failure
    stoppedAt = pausedAt ?? now
    phase = .failed
    return true
  }

  @discardableResult public mutating func beginFinishing(
    at now: TimeInterval, reason: SessionEndReason = .userFinished
  ) -> Bool {
    guard phase != .finishing, phase != .finished else { return false }
    if failure?.requiresAttention(ending: reason) == false { failure = nil }
    failure = failure ?? finalizationNotice
    stoppedAt = stoppedAt ?? pausedAt ?? now
    phase = .finishing
    return true
  }

  @discardableResult public mutating func completeFinishing() -> Bool {
    guard phase == .finishing else { return false }
    phase = .finished
    return true
  }

  public mutating func recordFinalizationNotice(_ notice: SessionFailure?) {
    guard phase != .finished else { return }
    finalizationNotice = finalizationNotice ?? notice
    if phase == .finishing { failure = failure ?? finalizationNotice }
  }

  public mutating func recordRecordingFailure(_ failure: SessionFailure) {
    guard phase == .finishing else { return }
    self.failure = failure
  }

  public func elapsed(at now: TimeInterval) -> TimeInterval {
    sampleElapsed(at: stoppedAt ?? pausedAt ?? now)
  }

  public func sampleElapsed(at capturedAt: TimeInterval) -> TimeInterval {
    guard let startedAt else { return 0 }
    return max(0, capturedAt - startedAt - pausedDuration)
  }
}
