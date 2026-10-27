import Foundation

/// Counts queued audio duration rather than assuming a particular hardware callback size.
public struct AudioInputBudget<Source: Hashable & Sendable>: Sendable {
  public enum Admission: Sendable { case accepted, full, invalid }
  public static var maximumQueuedSeconds: TimeInterval { 12 }
  private static var maximumQueuedCallbacks: Int { 4_096 }
  private var durations: [Source: TimeInterval] = [:]
  private var callbacks = 0

  public init() {}

  public mutating func reserve(duration: TimeInterval, source: Source) -> Admission {
    guard duration.isFinite, duration > 0 else { return .invalid }
    guard callbacks < Self.maximumQueuedCallbacks,
      durations[source, default: 0] + duration <= Self.maximumQueuedSeconds
    else { return .full }
    callbacks += 1
    durations[source, default: 0] += duration
    return .accepted
  }

  public mutating func release(duration: TimeInterval, source: Source) {
    callbacks = max(0, callbacks - 1)
    durations[source] = max(0, durations[source, default: 0] - duration)
  }
}
