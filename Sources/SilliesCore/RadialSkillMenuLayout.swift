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
    let centers = RadialMenuArc(count: skills.count).centers(around: center, facingDegrees: 90)
    return zip(skills, centers).map { skill, point in
      Item(
        skill: skill,
        center: CGPoint(
          x: point.x,
          y: direction == .downward ? center.y * 2 - point.y : point.y))
    }
  }

  private static func radius(for count: Int) -> Double {
    RadialMenuArc(count: count).radius
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
