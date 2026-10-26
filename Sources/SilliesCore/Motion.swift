import CoreGraphics
import Foundation

public struct PerchSurface: Equatable, Sendable {
  private static let horizontalInsetFactor: Double = 0.6
  private static let desktopBottomMargin: Double = 10
  private static let topHeadroomMargin: Double = 5
  private static let sideScreenMargin: Double = 6
  private static let compactHeadroomRatio: Double = 1.03
  private static let minimumCompactSize: Double = 40
  private static let minimumTopWidthFactor: Double = 1.4
  private static let sideBottomClearanceFactor: Double = 0.9
  private static let sideTopClearanceFactor: Double = 0.35
  private static let windowBorderGap: Double = 1
  private static let floatingPointRoundingSlop: Double = 1e-6

  private static func compactedPresentationSize(
    availableRoom: Double, characterSize: Double
  ) -> Double {
    let rawSize = availableRoom / compactHeadroomRatio
    guard rawSize < characterSize else { return characterSize }
    return (rawSize + floatingPointRoundingSlop).rounded(.down)
  }

  public enum Edge: String, Sendable { case top, left, right, desktop, unavailable }
  public let minX: Double
  public let maxX: Double
  public let y: Double
  public let edge: Edge
  public let presentationSize: Double
  public let start: CGPoint
  public let end: CGPoint

  public var isAvailable: Bool { edge != .unavailable }
  public var spanLength: Double { hypot(end.x - start.x, end.y - start.y) }
  public var angle: Double {
    switch edge {
    case .left: .pi / 2
    case .right: -.pi / 2
    default: 0
    }
  }
  public var outward: CGPoint {
    switch edge {
    case .left: CGPoint(x: -1, y: 0)
    case .right: CGPoint(x: 1, y: 0)
    default: CGPoint(x: 0, y: 1)
    }
  }

  /// Positions refer to the character's feet in AppKit's bottom-left coordinate space.
  public init(
    window: CGRect?, visibleFrame: CGRect, characterSize: Double, preferRight: Bool = false
  ) {
    guard let window else {
      edge = .desktop
      presentationSize = characterSize
      minX = visibleFrame.minX + characterSize * Self.horizontalInsetFactor
      maxX = max(minX, visibleFrame.maxX - characterSize * Self.horizontalInsetFactor)
      y = visibleFrame.minY + Self.desktopBottomMargin
      start = CGPoint(x: minX, y: y)
      end = CGPoint(x: maxX, y: y)
      return
    }
    let safe = window.intersection(visibleFrame)
    let headroom = visibleFrame.maxY - window.maxY - Self.topHeadroomMargin
    let topSize = Self.compactedPresentationSize(
      availableRoom: headroom, characterSize: characterSize)
    let leftRoom = window.minX - visibleFrame.minX - Self.sideScreenMargin
    let rightRoom = visibleFrame.maxX - window.maxX - Self.sideScreenMargin
    let minReadableSize = min(Self.minimumCompactSize, characterSize)
    if !safe.isNull, topSize >= minReadableSize, safe.width > topSize * Self.minimumTopWidthFactor {
      edge = .top
      presentationSize = topSize
      minX = safe.minX + topSize * Self.horizontalInsetFactor
      maxX = max(minX, safe.maxX - topSize * Self.horizontalInsetFactor)
      y = window.maxY + Self.windowBorderGap
      start = CGPoint(x: minX, y: y)
      end = CGPoint(x: maxX, y: y)
    } else if !safe.isNull,
      max(leftRoom, rightRoom) >= minReadableSize * Self.compactHeadroomRatio
    {
      let minimum = minReadableSize * Self.compactHeadroomRatio
      let right = preferRight ? rightRoom >= minimum : leftRoom < minimum
      edge = right ? .right : .left
      presentationSize = Self.compactedPresentationSize(
        availableRoom: right ? rightRoom : leftRoom, characterSize: characterSize)
      let low = safe.minY + presentationSize * Self.sideBottomClearanceFactor
      let high = max(low, safe.maxY - presentationSize * Self.sideTopClearanceFactor)
      minX = right ? window.maxX + Self.windowBorderGap : window.minX - Self.windowBorderGap
      maxX = minX
      y = high
      start = CGPoint(x: minX, y: right ? high : low)
      end = CGPoint(x: minX, y: right ? low : high)
    } else {
      edge = .unavailable
      presentationSize = characterSize
      minX = visibleFrame.midX
      maxX = minX
      y = visibleFrame.maxY
      start = CGPoint(x: minX, y: y)
      end = start
    }
  }

  public func point(at fraction: Double) -> CGPoint {
    let value = min(max(fraction, 0), 1)
    return CGPoint(x: start.x + (end.x - start.x) * value, y: start.y + (end.y - start.y) * value)
  }

  public func fraction(for x: Double) -> Double {
    guard maxX > minX else { return 0.5 }
    return min(max((x - minX) / (maxX - minX), 0), 1)
  }

  public func fraction(for point: CGPoint, fallback: Double = 0.5) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = dx * dx + dy * dy
    guard isAvailable, length > 0 else { return min(max(fallback, 0), 1) }
    return min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / length, 0), 1)
  }

  public func clamped(_ point: CGPoint) -> CGPoint {
    self.point(at: fraction(for: point))
  }

  public func isAtBoundary(_ point: CGPoint, tolerance: Double = 0.01) -> Bool {
    guard isAvailable, hypot(end.x - start.x, end.y - start.y) > 0 else { return false }
    let current = fraction(for: point)
    return current <= tolerance || current >= 1 - tolerance
  }
}

public struct StrollPlan: Equatable, Sendable {
  private static let minimumOffset: Double = 45
  private static let offsetSpan: Double = 110
  private static let minimumTravelDistance: Double = 4

  public let target: CGPoint
  public let duration: Double
  public let facingRight: Bool
  public let reachesEdge: Bool

  public init?(
    from position: CGPoint, on surface: PerchSurface, speed: Double, activity: Double,
    maxDuration: Double, occupied: [PerchReservation] = [], random: inout SeededRandom
  ) {
    let direction = random.unit() < 0.5 ? -1.0 : 1.0
    let offset = direction * (Self.minimumOffset + random.unit() * Self.offsetSpan)
    let length = hypot(surface.end.x - surface.start.x, surface.end.y - surface.start.y)
    let currentFraction = surface.fraction(for: position)
    let rawFraction = currentFraction + offset / max(length, 1)
    guard
      let targetPoint = PerchSpacing.nearestAvailablePoint(
        to: surface.point(at: rawFraction), on: surface, occupied: occupied)
    else { return nil }
    let distance = hypot(targetPoint.x - position.x, targetPoint.y - position.y)
    guard distance > Self.minimumTravelDistance else { return nil }
    target = targetPoint
    facingRight = surface.fraction(for: targetPoint) > currentFraction
    reachesEdge = surface.isAtBoundary(targetPoint)
    duration = min(maxDuration, distance / max(speed * activity, 1))
  }
}

public struct WindowMotionFeedback: Equatable, Sendable {
  public static let velocityToLeanScale: Double = 2200
  public static let maxLeanAngle: Double = 0.20
  public static let widthSpeedToStretchScale: Double = 3000
  public static let maxStretch: Double = 0.12

  public let lean: Double
  public let stretch: Double

  public init(
    edge: PerchSurface.Edge, horizontalSpeed: Double, verticalSpeed: Double,
    widthSpeed: Double, resized: Bool
  ) {
    let speed = edge == .top ? horizontalSpeed : verticalSpeed
    lean = min(max(-speed / Self.velocityToLeanScale, -Self.maxLeanAngle), Self.maxLeanAngle)
    stretch =
      resized
      ? min(
        max(widthSpeed / Self.widthSpeedToStretchScale, -Self.maxStretch), Self.maxStretch)
      : 0
  }
}

public enum NeighborProximity {
  public static let orthogonalTolerance: Double = 20

  public static func nearbyIndices(
    positions: [CGPoint], edges: [PerchSurface.Edge], size: Double
  ) -> Set<Int> {
    guard positions.count > 1, positions.count == edges.count else { return [] }
    var nearby: Set<Int> = []
    for i in 0..<positions.count where edges[i] != .unavailable {
      for j in (i + 1)..<positions.count where edges[j] == edges[i] {
        let dx = abs(positions[i].x - positions[j].x)
        let dy = abs(positions[i].y - positions[j].y)
        let isVertical = edges[i] == .left || edges[i] == .right
        let alongDistance = isVertical ? dy : dx
        let crossDistance = isVertical ? dx : dy
        if alongDistance < size && crossDistance < orthogonalTolerance {
          nearby.insert(i)
          nearby.insert(j)
        }
      }
    }
    return nearby
  }
}

public enum MotionCurve: Sendable {
  case smooth, linear, accelerating
}

public struct MotionTween: Sendable {
  private static let minimumDuration: Double = 0.001

  public let start: CGPoint
  public let end: CGPoint
  public let startedAt: TimeInterval
  public let duration: Double
  public let arcHeight: Double
  public let curve: MotionCurve
  public let arcDirection: CGPoint

  public init(
    from start: CGPoint, to end: CGPoint, at time: TimeInterval,
    duration: Double, arcHeight: Double = 0, curve: MotionCurve = .smooth,
    arcDirection: CGPoint = CGPoint(x: 0, y: 1)
  ) {
    self.start = start
    self.end = end
    startedAt = time
    self.duration = max(duration, Self.minimumDuration)
    self.arcHeight = arcHeight
    self.curve = curve
    self.arcDirection = arcDirection
  }

  public func position(at time: TimeInterval) -> CGPoint {
    let t = min(max((time - startedAt) / duration, 0), 1)
    let eased: Double
    switch curve {
    case .smooth: eased = t * t * (3 - 2 * t)
    case .linear: eased = t
    case .accelerating: eased = t * t
    }
    let lift = 4 * arcHeight * t * (1 - t)
    return CGPoint(
      x: start.x + (end.x - start.x) * eased + arcDirection.x * lift,
      y: start.y + (end.y - start.y) * eased + arcDirection.y * lift)
  }

  public func isComplete(at time: TimeInterval) -> Bool { time >= startedAt + duration }
}

public enum ScreenCoordinates {
  public static func appKitRect(fromAccessibility rect: CGRect, primaryScreenTop: Double) -> CGRect
  {
    CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
  }
}

/// A small throttle for noisy input sources. Priority events bypass it at the router.
public struct EventThrottle: Sendable {
  private var lastEmission: [EventKind: TimeInterval] = [:]
  public init() {}
  public mutating func accepts(_ event: WorkspaceEvent, interval: Double) -> Bool {
    guard event.timestamp - (lastEmission[event.kind] ?? -.infinity) >= interval else {
      return false
    }
    lastEmission[event.kind] = event.timestamp
    return true
  }
}
