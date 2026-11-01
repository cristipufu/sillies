import Foundation

/// The UI keeps the complete history. Reasoning alone chooses the model's working context.
public struct ChatContext: Sendable {
  public static let maximumMessageCharacters = 2_000
  public static let maximumMessageBytes = 16_000
  public let companionName: String
  public let profile: CharacterChatProfile
  public let messages: [ChatMessage]
  public let memory: ConversationMemory
  public let turnID: UUID

  public init(
    companionName: String, profile: CharacterChatProfile, messages: [ChatMessage],
    memory: ConversationMemory = .init(), turnID: UUID = UUID()
  ) {
    self.companionName = companionName
    self.profile = profile
    self.messages = messages
    self.memory = memory
    self.turnID = turnID
  }
}
