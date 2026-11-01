import Foundation

public struct ConversationToolCall: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  /// The native runtime's JSON arguments; each registered tool decodes its own argument type.
  public let arguments: Data
  public init(id: String, name: String, arguments: Data) {
    self.id = id
    self.name = name
    self.arguments = arguments
  }
}
