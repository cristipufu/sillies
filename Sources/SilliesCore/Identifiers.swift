import Foundation

/// Open identifiers keep character packs extensible without editing a central enum.
public struct EventKind: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let ambient: Self = "ambient"
  public static let ambientWall: Self = "ambient.wall"
  public static let appChanged: Self = "appChanged"
  public static let windowMoved: Self = "windowMoved"
  public static let windowResized: Self = "windowResized"
  public static let windowSettled: Self = "windowSettled"
  public static let edgeReached: Self = "edgeReached"
  public static let windowDisappeared: Self = "windowDisappeared"
  public static let contextChanged: Self = "contextChanged"
  public static let scroll: Self = "scroll"
  public static let pet: Self = "pet"
  public static let pickedUp: Self = "pickedUp"
  public static let dropped: Self = "dropped"
  public static let userIdle: Self = "userIdle"
  public static let userReturned: Self = "userReturned"
  public static let neighbor: Self = "neighbor"
  public static let skillSnap: Self = "skill.snap"
  public static let skillListen: Self = "skill.listen"
  public static let skillWatch: Self = "skill.watch"
  public static let skillFocus: Self = "skill.focus"
  public static let skillCompleted: Self = "skill.completed"
  public static let stashReceived: Self = "stash.received"
}

public struct AnimationID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral
{
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let idle: Self = "idle"
  public static let walk: Self = "walk"
  public static let sleep: Self = "sleep"
  public static let surprised: Self = "surprised"
  public static let balance: Self = "balance"
  public static let wave: Self = "wave"
  public static let happy: Self = "happy"
  public static let tumble: Self = "tumble"
  public static let peek: Self = "peek"
  public static let meditate: Self = "meditate"
  public static let brace: Self = "brace"
  public static let scramble: Self = "scramble"
  public static let land: Self = "land"
  public static let appear: Self = "appear"
  public static let disappear: Self = "disappear"
  public static let hang: Self = "hang"
  public static let climb: Self = "climb"
  public static let hangCatch: Self = "hangCatch"
  public static let snap: Self = "snap"
  public static let listen: Self = "listen"
  public static let watch: Self = "watch"
  public static let focus: Self = "focus"
}

public struct WorkspaceEvent: Sendable {
  public var kind: EventKind
  public var timestamp: TimeInterval
  public var intensity: Double

  public init(_ kind: EventKind, at timestamp: TimeInterval, intensity: Double = 1) {
    self.kind = kind
    self.timestamp = timestamp
    self.intensity = min(max(intensity, 0), 1)
  }
}
