/// Application policy, supplied by the selected backend. Byte limits remain separate transport guards.
public struct ConversationPolicy: Codable, Equatable, Sendable {
  public struct Compaction: Codable, Equatable, Sendable {
    public let summaryWords: Int
    public let headroomTokens: Int
    public init(summaryWords: Int, headroomTokens: Int) {
      self.summaryWords = summaryWords
      self.headroomTokens = headroomTokens
    }
  }

  public struct Tools: Codable, Equatable, Sendable {
    public let maximumCalls: Int
    public let reserveTokens: Int
    public let resultTokens: Int
    public init(maximumCalls: Int, reserveTokens: Int, resultTokens: Int) {
      self.maximumCalls = maximumCalls
      self.reserveTokens = reserveTokens
      self.resultTokens = resultTokens
    }
  }

  public struct History: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
      public let messageLimit: Int
      public let byteLimit: Int
      public init(messageLimit: Int, byteLimit: Int) {
        self.messageLimit = messageLimit
        self.byteLimit = byteLimit
      }
      var isValid: Bool {
        (2...ConversationPageRequest.maximumLimit).contains(messageLimit)
          && (1...ConversationPageRequest.maximumPageBytes).contains(byteLimit)
      }
    }
    public struct Checkpoint: Codable, Equatable, Sendable {
      public let window: Window
      public let minimumMessages: Int
      public init(window: Window, minimumMessages: Int) {
        self.window = window
        self.minimumMessages = minimumMessages
      }
    }
    public let recent: Window
    public let checkpoint: Checkpoint
    public init(recent: Window, checkpoint: Checkpoint) {
      self.recent = recent
      self.checkpoint = checkpoint
    }
    public static let bounded = Self(
      recent: .init(messageLimit: 64, byteLimit: 32_768),
      checkpoint: .init(window: .init(messageLimit: 24, byteLimit: 12_288), minimumMessages: 12))
    public var isValid: Bool {
      recent.isValid && checkpoint.window.isValid
        && checkpoint.minimumMessages > 0
        && checkpoint.minimumMessages < checkpoint.window.messageLimit
    }
  }

  public let safetyTokens: Int
  public let compaction: Compaction
  public let tools: Tools
  public let history: History
  public init(safetyTokens: Int, compaction: Compaction, tools: Tools) {
    self.init(safetyTokens: safetyTokens, compaction: compaction, tools: tools, history: .bounded)
  }
  public init(safetyTokens: Int, compaction: Compaction, tools: Tools, history: History) {
    self.safetyTokens = safetyTokens
    self.compaction = compaction
    self.tools = tools
    self.history = history
  }
  public var isValid: Bool {
    safetyTokens > 0 && compaction.summaryWords > 0 && compaction.headroomTokens >= 0
      && tools.maximumCalls > 0 && tools.maximumCalls <= Self.maximumToolCalls
      && tools.reserveTokens > 0 && tools.resultTokens > 0
      && tools.resultTokens <= tools.reserveTokens
      && history.isValid
  }
  private static let maximumToolCalls = 32
}
