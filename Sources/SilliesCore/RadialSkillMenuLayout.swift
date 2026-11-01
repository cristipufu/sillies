import CoreGraphics
import Foundation

/// Pure geometric layout and hit-testing for the radial skill wheel around a dragged companion.
public struct RadialSkillMenuLayout: Equatable, Sendable {
  public enum Direction: Sendable { case upward, downward }

  public struct Item: Equatable, Sendable, Identifiable {
    public let skill: CompanionSkillKind
    public let center: CGPoint
    public var id: CompanionSkillKind { skill }
  }

  public static let orbitRadius = radius(for: CompanionSkillKind.radialSkills.count)
  public static let bubbleHitRadius: Double = 36
  public static let screenMargin = orbitRadius + bubbleHitRadius + screenEdgePadding
  private static let screenEdgePadding: Double = 2
  private static let topFlipClearanceMargin: Double = 12
  private static let edgeAngleDegrees: Double = 14
  private static let arcDegrees = 180 - edgeAngleDegrees * 2
  private static let minimumOrbitRadius: Double = 118
  private static let targetGap: Double = 8

  public let interactionRadius: Double
  public let anchor: CGPoint
  public let items: [Item]

  public init(
    center: CGPoint, visibleFrame: CGRect,
    skills: [CompanionSkillKind] = CompanionSkillKind.radialSkills
  ) {
    let radius = Self.radius(for: skills.count)
    interactionRadius = radius + Self.bubbleHitRadius
    let margin = interactionRadius + Self.screenEdgePadding
    let clampedX = min(
      max(center.x, visibleFrame.minX + margin),
      visibleFrame.maxX - margin)
    let clampedY = min(
      max(center.y, visibleFrame.minY + margin),
      visibleFrame.maxY - margin)
    let clampedAnchor = CGPoint(x: clampedX, y: clampedY)
    anchor = clampedAnchor
    let flipDownward =
      clampedAnchor.y + radius + Self.bubbleHitRadius
      > visibleFrame.maxY - Self.topFlipClearanceMargin
    items = Self.items(
      around: clampedAnchor, direction: flipDownward ? .downward : .upward, skills: skills)
  }

  public static func items(
    around center: CGPoint, direction: Direction,
    skills: [CompanionSkillKind] = CompanionSkillKind.radialSkills
  ) -> [Item] {
    let radius = radius(for: skills.count)
    return skills.enumerated().map { index, skill in
      let fraction = skills.count > 1 ? Double(index) / Double(skills.count - 1) : 0.5
      let degrees = 180 - edgeAngleDegrees - fraction * arcDegrees
      let radians = degrees * .pi / 180 * (direction == .downward ? -1 : 1)
      return Item(
        skill: skill,
        center: CGPoint(
          x: center.x + cos(radians) * radius,
          y: center.y + sin(radians) * radius))
    }
  }

  private static func radius(for count: Int) -> Double {
    guard count > 1 else { return minimumOrbitRadius }
    let angularGap = arcDegrees * .pi / 180 / Double(count - 1)
    let required = (bubbleHitRadius * 2 + targetGap) / (2 * sin(angularGap / 2))
    return max(minimumOrbitRadius, required)
  }

  public func selectedSkill(at pointer: CGPoint) -> CompanionSkillKind? {
    items.min {
      hypot($0.center.x - pointer.x, $0.center.y - pointer.y)
        < hypot($1.center.x - pointer.x, $1.center.y - pointer.y)
    }.flatMap { nearest in
      hypot(nearest.center.x - pointer.x, nearest.center.y - pointer.y) <= Self.bubbleHitRadius
        ? nearest.skill : nil
    }
  }
}
