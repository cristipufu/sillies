import Foundation

public struct VaultCollection: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public init(id: UUID = UUID(), name: String) {
    self.id = id
    self.name = name
  }
}
