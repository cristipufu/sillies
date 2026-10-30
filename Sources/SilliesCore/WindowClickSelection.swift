import Foundation

public struct WindowClickSelection: Sendable {
  public init() {}
  public private(set) var point: CGPoint?
  public private(set) var capturedAt: Double = 0
  public private(set) var resolvedProcessID: Int32 = 0

  public mutating func record(at newPoint: CGPoint, now: Double) {
    point = newPoint
    capturedAt = now
    resolvedProcessID = 0
  }

  public mutating func clear() {
    point = nil
  }

  public mutating func markResolved(for processID: Int32) {
    if point != nil {
      resolvedProcessID = processID
    }
  }

  public func isActive(at now: Double, expiration: Double) -> Bool {
    point != nil && now - capturedAt < expiration
  }

  public func activePoint(for processID: Int32, at now: Double, expiration: Double) -> CGPoint? {
    guard let point,
      resolvedProcessID != processID,
      now - capturedAt < expiration
    else { return nil }
    return point
  }
}
