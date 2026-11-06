import Foundation

/// A bounded working set. Durable originals belong to the conversation repository.
public struct ChatContext: Sendable {
  public enum HistoryCoverage: Sendable {
    case includesCheckpoint, followsCheckpoint, recentWindow
  }
  public static let maximumMessageCharacters = 2_000
  public static let maximumMessageBytes = 16_000
  public let companionName: String
  public let profile: CharacterChatProfile
  public private(set) var messages: [ChatMessage]
  public private(set) var memory: ConversationMemory
  public private(set) var selectedRecords = ConversationRecordSelection()
  public private(set) var background = ConversationBackground()
  public private(set) var mode = ConversationMode.chat
  public private(set) var turnID = UUID()
  public private(set) var sessionID: UUID?
  public private(set) var historyHandle: ConversationHandle?
  public private(set) var historyCoverage = HistoryCoverage.includesCheckpoint

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
  public func inHistory(_ handle: ConversationHandle?) -> Self {
    var copy = self
    copy.historyHandle = handle
    return copy
  }

  public func presented(as mode: ConversationMode) -> Self {
    var copy = self
    copy.mode = mode
    return copy
  }

  public func selecting(_ records: ConversationRecordSelection) -> Self {
    var copy = self
    copy.selectedRecords = records
    return copy
  }

  public func prepared(with background: ConversationBackground) -> Self {
    var copy = self
    copy.background = background
    return copy
  }

  /// Replace only the bounded working history; retain the turn's explicit context and identity.
  public func replacingHistory(messages: [ChatMessage], memory: ConversationMemory) -> Self {
    var copy = self
    copy.messages = messages
    copy.memory = memory
    return copy
  }

  /// Used only after repository paging or compaction establishes the checkpoint boundary.
  public func followingCheckpoint() -> Self {
    var copy = self
    copy.historyCoverage = .followsCheckpoint
    return copy
  }

  /// A bounded recent window may leave an unsummarized gap; original messages remain searchable.
  public func coveringRecentWindow() -> Self {
    var copy = self
    copy.historyCoverage = .recentWindow
    return copy
  }
}
