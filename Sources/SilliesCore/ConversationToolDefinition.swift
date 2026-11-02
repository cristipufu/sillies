import Foundation

/// Provider-independent function metadata. Native adapters own schema translation.
public struct ConversationToolDefinition: Codable, Equatable, Sendable {
  public struct Parameter: Codable, Equatable, Sendable {
    public enum Requirement: String, Codable, Sendable { case required, optional }
    public enum Kind: Codable, Equatable, Sendable {
      case string, integer, boolean
      case choice([String])
    }
    public let name: String
    public let description: String
    public let kind: Kind
    public let requirement: Requirement
    public init(
      _ name: String, description: String, kind: Kind = .string,
      requirement: Requirement = .required
    ) {
      self.name = name
      self.description = description
      self.kind = kind
      self.requirement = requirement
    }

    private enum CodingKeys: String, CodingKey { case name, description, kind, requirement }
    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      name = try values.decode(String.self, forKey: .name)
      description = try values.decode(String.self, forKey: .description)
      kind = try values.decode(Kind.self, forKey: .kind)
      requirement = try values.decodeIfPresent(Requirement.self, forKey: .requirement) ?? .required
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
