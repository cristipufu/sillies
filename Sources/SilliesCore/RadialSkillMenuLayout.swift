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

  public static let orbitRadius: Double = 118
  public static let bubbleHitRadius: Double = 36
  public static let screenMargin: Double = 156
  private static let topFlipClearanceMargin: Double = 12
  private static let upwardAnglesDegrees: [Double] = [166, 128, 90, 52, 14]
  private static let downwardAnglesDegrees: [Double] = [-166, -128, -90, -52, -14]

  public let anchor: CGPoint
  public let items: [Item]

  public init(
    center: CGPoint, visibleFrame: CGRect,
    skills: [CompanionSkillKind] = CompanionSkillKind.radialSkills
  ) {
    let clampedX = min(
      max(center.x, visibleFrame.minX + Self.screenMargin),
      visibleFrame.maxX - Self.screenMargin)
    let clampedY = min(
      max(center.y, visibleFrame.minY + Self.screenMargin),
      visibleFrame.maxY - Self.screenMargin)
    let clampedAnchor = CGPoint(x: clampedX, y: clampedY)
    anchor = clampedAnchor
    let flipDownward =
      clampedAnchor.y + Self.orbitRadius + Self.bubbleHitRadius
      > visibleFrame.maxY - Self.topFlipClearanceMargin
    items = Self.items(
      around: clampedAnchor, direction: flipDownward ? .downward : .upward, skills: skills)
  }

  public static func items(
    around center: CGPoint, direction: Direction,
    skills: [CompanionSkillKind] = CompanionSkillKind.radialSkills
  ) -> [Item] {
    let angles = direction == .downward ? downwardAnglesDegrees : upwardAnglesDegrees
    return zip(skills, angles).map { skill, degrees in
      let radians = degrees * .pi / 180
      return Item(
        skill: skill,
        center: CGPoint(
          x: center.x + cos(radians) * orbitRadius,
          y: center.y + sin(radians) * orbitRadius))
    }
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
