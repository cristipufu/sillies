/// Native adapter capabilities reviewed for a checkpoint. Defaults preserve its existing runtime.
public struct TextModelRuntimePolicy: Codable, Equatable, Sendable {
  public enum ConversationCache: String, Codable, Sendable {
    case disabled, nativeSession, prefixSnapshot
  }
  public enum ChatTemplate: String, Codable, Sendable { case checkpoint, mistral3 }

  public struct PrefixSnapshot: Codable, Equatable, Sendable {
    public let maximumTokens: Int
    /// Logical native state-array bytes. The helper's allocation budget also covers weights,
    /// live generation, allocator padding and temporary work; this is not a process RSS limit.
    public let maximumBytes: Int
    public var isValid: Bool { maximumTokens > 0 && maximumBytes > 0 }
    public init(maximumTokens: Int, maximumBytes: Int) {
      self.maximumTokens = maximumTokens
      self.maximumBytes = maximumBytes
    }
  }

  public let conversationCache: ConversationCache
  public let chatTemplate: ChatTemplate
  public let prefixSnapshot: PrefixSnapshot?
  public var isValid: Bool {
    switch conversationCache {
    case .prefixSnapshot: prefixSnapshot?.isValid == true
    case .disabled, .nativeSession: prefixSnapshot == nil
    }
  }
  public init(
    conversationCache: ConversationCache, chatTemplate: ChatTemplate,
    prefixSnapshot: PrefixSnapshot? = nil
  ) {
    self.conversationCache = conversationCache
    self.chatTemplate = chatTemplate
    self.prefixSnapshot = prefixSnapshot
  }
  public static let standard = Self(conversationCache: .disabled, chatTemplate: .checkpoint)
}
