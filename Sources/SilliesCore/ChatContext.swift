import Foundation

/// The UI keeps the complete history. Reasoning alone chooses the model's working context.
public struct ChatContext: Sendable {
  public static let maximumMessageCharacters = 2_000
  public static let maximumMessageBytes = 16_000
  public let companionName: String
  public let profile: CharacterChatProfile
  public let messages: [ChatMessage]
  public let memory: ConversationMemory
  public private(set) var turnID = UUID()
  public private(set) var sessionID: UUID?

  public init(
    companionName: String, profile: CharacterChatProfile, messages: [ChatMessage],
    memory: ConversationMemory = .init()
  ) {
    self.companionName = companionName
    self.profile = profile
    self.messages = messages
    self.memory = memory
  }

  public func inTurn(_ id: UUID, session: UUID?) -> Self {
    var copy = self
    copy.turnID = id
    copy.sessionID = session
    return copy
  }
}
