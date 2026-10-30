import Foundation

/// Shared displacement keeps a cast and its prop connected during a struggle or glide.
public struct PlayfulSceneMotion: Codable, Equatable, Sendable {
  public enum Direction: String, Codable, Sendable { case alternating, outward }
  public let direction: Direction
  public let distance: Double
  public let cycles: Int
  public let bank: Double

  public var isValid: Bool {
    distance.isFinite && (0...0.6).contains(distance)
      && (1...3).contains(cycles) && bank.isFinite && (0...0.15).contains(bank)
  }

  public init(direction: Direction, distance: Double, cycles: Int, bank: Double = 0) {
    self.direction = direction
    self.distance = distance
    self.cycles = cycles
    self.bank = bank
  }

  public func offset(at progress: Double, size: Double) -> Double {
    let phase = min(max(progress, 0), 1)
    let angle = phase * Double(cycles) * 2 * .pi
    let wave = direction == .outward ? (1 - cos(angle)) / 2 : sin(angle) * sin(.pi * phase)
    return distance * size * wave
  }

  public func bankAngle(at progress: Double) -> Double {
    let phase = min(max(progress, 0), 1)
    return -bank * sin(phase * Double(cycles) * 2 * .pi) * sin(.pi * phase)
  }
}
