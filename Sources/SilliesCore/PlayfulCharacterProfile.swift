import Foundation

public struct PlayfulCharacterProfile: Codable, Sendable, Equatable {
  public let scenes: [String]
  public let clips: [String: String]
  public let signs: [String]

  public func animation(for shared: AnimationID) -> AnimationID {
    AnimationID(rawValue: clips[shared.rawValue] ?? shared.rawValue)
  }

  public func validate() throws {
    guard Set(scenes).count == scenes.count, scenes.allSatisfy({ !$0.isEmpty }),
      clips.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }),
      signs.allSatisfy({ !$0.isEmpty && $0.count <= 80 })
    else { throw CharacterDefinition.ValidationError("Invalid playful character profile") }
  }
}
