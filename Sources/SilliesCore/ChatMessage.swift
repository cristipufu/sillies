import Foundation

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
  public enum Role: String, Codable, Sendable { case user, companion }
  public let id: UUID
  public let role: Role
  public let text: String

  public init(id: UUID = UUID(), role: Role, text: String) {
    self.id = id
    self.role = role
    self.text = text
  }
}

public struct ChatContext: Sendable {
  public static let maximumCharacters = 6_000
  public static let maximumMessageCharacters = 2_000
  public let companionName: String
  public let profile: CharacterChatProfile
  public let messages: [ChatMessage]

  public init(companionName: String, profile: CharacterChatProfile, messages: [ChatMessage]) {
    self.companionName = companionName
    self.profile = profile
    var remaining = Self.maximumCharacters
    var selected: [ChatMessage] = []
    for message in messages.reversed() {
      guard message.text.count <= remaining else { break }
      remaining -= message.text.count
      selected.append(message)
    }
    self.messages = selected.reversed()
  }
}
