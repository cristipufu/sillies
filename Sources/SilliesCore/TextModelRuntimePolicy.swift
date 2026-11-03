/// Native adapter capabilities reviewed for a checkpoint. Defaults preserve its existing runtime.
public struct TextModelRuntimePolicy: Codable, Equatable, Sendable {
  public enum ConversationCache: String, Codable, Sendable { case disabled, nativeSession }
  public enum ChatTemplate: String, Codable, Sendable { case checkpoint, mistral3 }

  public let conversationCache: ConversationCache
  public let chatTemplate: ChatTemplate
  public init(conversationCache: ConversationCache, chatTemplate: ChatTemplate) {
    self.conversationCache = conversationCache
    self.chatTemplate = chatTemplate
  }
  public static let standard = Self(conversationCache: .disabled, chatTemplate: .checkpoint)
}
