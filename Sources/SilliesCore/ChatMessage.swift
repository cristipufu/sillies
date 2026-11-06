import Foundation

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
  public enum Role: String, Codable, Sendable { case user, companion }
  public let id: UUID
  public let role: Role
  public private(set) var text: String
  public private(set) var sources: [ChatSource]
  public private(set) var exchanges: [ConversationToolExchange]
  public private(set) var contextInspection: ReplyContextInspection?
  public private(set) var clarification: ChatClarification?
  public func asking(_ question: ChatClarification?) -> Self {
    var copy = self
    copy.clarification = question
    return copy
  }
  public enum Completion: String, Codable, Sendable { case streaming, complete, interrupted }
  private struct Delivery: Codable, Equatable, Sendable {
    let completion: Completion
    let spokenText: String?
  }
  private var delivery: Delivery?
  public var completion: Completion? { delivery?.completion }
  public var spokenText: String? { delivery?.spokenText }

  public init(id: UUID = UUID(), role: Role, text: String, evidence: Evidence = .init()) {
    self.id = id
    self.role = role
    self.text = text
    sources = evidence.sources
    exchanges = evidence.exchanges

  }
  public func withDelivery(_ completion: Completion, spokenText: String?) -> Self {
    var copy = self
    copy.delivery = Delivery(completion: completion, spokenText: spokenText)
    return copy
  }
  public func inspecting(_ context: ReplyContextInspection?) -> Self {
    var copy = self
    copy.contextInspection = context
    return copy
  }
  public func withText(_ text: String) -> Self {
    var copy = self
    copy.text = text
    return copy
  }
  public func withEvidence(_ evidence: Evidence) -> Self {
    var copy = self
    copy.sources = evidence.sources
    copy.exchanges = evidence.exchanges
    return copy
  }
  public struct Evidence: Sendable {
    public let sources: [ChatSource]
    public let exchanges: [ConversationToolExchange]
    public init(sources: [ChatSource] = [], exchanges: [ConversationToolExchange] = []) {
      self.sources = sources
      self.exchanges = exchanges
    }
  }
}
