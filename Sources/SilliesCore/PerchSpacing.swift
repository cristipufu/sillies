import CoreGraphics
import Foundation

/// A resting spot, or the reserved destination of a companion still walking toward it.
public struct PerchReservation: Sendable {
  public let point: CGPoint
  public let surface: PerchSurface

  public init(point: CGPoint, surface: PerchSurface) {
    self.point = point
    self.surface = surface
  }
}

/// Reserves distinct stopping spots. Travel paths may cross freely.
public enum PerchSpacing {
  private static let bodySpanRatio: Double = 1.2
  private static let restingGap: Double = 6
  private static let greetingMargin: Double = 12
  private static let tolerance: Double = 0.001

  public static func separation(between firstSize: Double, and secondSize: Double) -> Double {
    (firstSize + secondSize) * bodySpanRatio / 2 + restingGap
  }

  public static func greetingDistance(for size: Double) -> Double {
    separation(between: size, and: size) + greetingMargin
  }

  /// Keep the crew's order when a resize crowds an entire resting group.
  public static func restingPoints(
    near preferred: [CGPoint], on surface: PerchSurface
  ) -> [CGPoint?] {
    guard surface.isAvailable else { return preferred.map { _ in nil } }
    let vertical = surface.edge == .left || surface.edge == .right
    let coordinate: (CGPoint) -> Double = { vertical ? $0.y : $0.x }
    let lower = min(coordinate(surface.start), coordinate(surface.end))
    let upper = max(coordinate(surface.start), coordinate(surface.end))
    let gap = separation(between: surface.presentationSize, and: surface.presentationSize)
    let capacity = Int((upper - lower + tolerance) / gap) + 1
    let order = preferred.indices.sorted {
      coordinate(preferred[$0]) == coordinate(preferred[$1])
        ? $0 < $1 : coordinate(preferred[$0]) < coordinate(preferred[$1])
    }
    let visible = Array(order.prefix(capacity))
    guard !visible.isEmpty else { return [] }
    var coordinates = visible.map { min(max(coordinate(preferred[$0]), lower), upper) }
    for index in coordinates.indices.dropFirst() {
      coordinates[index] = max(coordinates[index], coordinates[index - 1] + gap)
    }
    let last = coordinates.count - 1
    coordinates[last] = min(coordinates[last], upper)
    if last > 0 {
      for index in stride(from: last - 1, through: 0, by: -1) {
        coordinates[index] = min(coordinates[index], coordinates[index + 1] - gap)
      }
    }
    var result = [CGPoint?](repeating: nil, count: preferred.count)
    for (index, slot) in visible.enumerated() {
      result[slot] =
        vertical
        ? CGPoint(x: surface.start.x, y: coordinates[index])
        : CGPoint(x: coordinates[index], y: surface.start.y)
    }
    return result
  }

  public static func nearestAvailablePoint(
    to preferred: CGPoint, on surface: PerchSurface, occupied: [PerchReservation]
  ) -> CGPoint? {
    guard surface.isAvailable else { return nil }
    let vertical = surface.edge == .left || surface.edge == .right
    let coordinate: (CGPoint) -> Double = { vertical ? $0.y : $0.x }
    let crossCoordinate: (CGPoint) -> Double = { vertical ? $0.x : $0.y }
    let lower = min(coordinate(surface.start), coordinate(surface.end))
    let upper = max(coordinate(surface.start), coordinate(surface.end))
    let desired = min(max(coordinate(preferred), lower), upper)
    let neighbors = occupied.filter {
      $0.surface.edge == surface.edge
        && abs(crossCoordinate($0.point) - crossCoordinate(surface.start))
          < separation(between: surface.presentationSize, and: $0.surface.presentationSize)
    }
    let candidates =
      [desired, lower, upper]
      + neighbors.flatMap { neighbor in
        let gap = separation(
          between: surface.presentationSize, and: neighbor.surface.presentationSize)
        return [coordinate(neighbor.point) - gap, coordinate(neighbor.point) + gap]
      }
    let available = candidates.filter { candidate in
      candidate >= lower - tolerance && candidate <= upper + tolerance
        && neighbors.allSatisfy {
          abs(candidate - coordinate($0.point)) + tolerance
            >= separation(between: surface.presentationSize, and: $0.surface.presentationSize)
        }
    }
    guard
      let nearest = available.min(by: {
        let lhs = abs($0 - desired)
        let rhs = abs($1 - desired)
        return abs(lhs - rhs) < tolerance ? $0 < $1 : lhs < rhs
      })
    else { return nil }
    let clamped = min(max(nearest, lower), upper)
    return vertical
      ? CGPoint(x: surface.start.x, y: clamped)
      : CGPoint(x: clamped, y: surface.start.y)
  }
}
