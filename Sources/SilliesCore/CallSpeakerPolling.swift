import CoreGraphics
import Foundation

/// Uses the skill clock; a moving or unavailable window invalidates the current read.
public struct CallSpeakerPolling {
  public static let interval: TimeInterval = 0.5
  public static let movementQuietPeriod: TimeInterval = 0.6
  private var frame: CGRect?
  private var quietSince: TimeInterval?
  private var lastRead: TimeInterval?
  public init() {}

  public mutating func isSettled(frame: CGRect, at now: TimeInterval) -> Bool {
    guard now.isFinite else { return false }
    if self.frame != frame {
      self.frame = frame
      quietSince = now
    }
    return quietSince.map { now >= $0 + Self.movementQuietPeriod } ?? false
  }

  public mutating func takeRead(at now: TimeInterval) -> Bool {
    guard now.isFinite, lastRead.map({ now >= $0 + Self.interval }) ?? true else { return false }
    lastRead = now
    return true
  }

  public mutating func suspend() {
    frame = nil
    quietSince = nil
    lastRead = nil
  }
}
