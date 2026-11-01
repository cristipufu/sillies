import Foundation

/// Provider-independent function metadata. Native adapters own schema translation.
public struct ConversationToolDefinition: Codable, Equatable, Sendable {
  public struct Parameter: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
      case string, integer, boolean
      case choice([String])
    }
    public let name: String
    public let description: String
    public let kind: Kind
    public init(_ name: String, description: String, kind: Kind = .string) {
      self.name = name
      self.description = description
      self.kind = kind
    }
  }
  public let name: String
  public let description: String
  public let parameters: [Parameter]
  public init(name: String, description: String, parameters: [Parameter]) {
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}
