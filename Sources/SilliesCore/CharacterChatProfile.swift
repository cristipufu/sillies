import Foundation

/// Character authors own personality and preferred voices; controllers never switch on character IDs.
public struct CharacterChatProfile: Codable, Equatable, Sendable {
  public static let maximumPersonalityCharacters = 1_000
  public let personality: String
  public let languageIdentifier: String
  public let preferredVoices: [String: String]

  public init(
    personality: String, languageIdentifier: String = "en", preferredVoices: [String: String] = [:]
  ) {
    self.personality = personality
    self.languageIdentifier = languageIdentifier
    self.preferredVoices = preferredVoices
  }

  public func validate() throws {
    guard !personality.isEmpty, personality.count <= Self.maximumPersonalityCharacters,
      !languageIdentifier.isEmpty, languageIdentifier.count <= 35,
      preferredVoices.count <= 32,
      preferredVoices.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty })
    else { throw CharacterDefinition.ValidationError("Invalid character Chat profile") }
  }
}
