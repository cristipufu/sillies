import Foundation

public struct CommandShortcut: Codable, Equatable, Hashable, Sendable {
  public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
  }
  public let keyCode: UInt32
  public let modifiers: Modifiers
  public let keyLabel: String

  public init(keyCode: UInt32, modifiers: Modifiers, keyLabel: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.keyLabel = keyLabel
  }

  public var isValid: Bool {
    keyCode < 128 && !modifiers.intersection([.command, .option, .control]).isEmpty
      && !keyLabel.isEmpty
  }
  public func conflicts(with other: Self) -> Bool {
    keyCode == other.keyCode && modifiers == other.modifiers
  }
  public var display: String {
    [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
      .filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
  }
}
