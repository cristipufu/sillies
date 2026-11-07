import Foundation

public struct VaultSavedSearch: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var query: VaultWorkspaceQuery
  public init(id: UUID = UUID(), name: String, query: VaultWorkspaceQuery) {
    self.id = id
    self.name = name
    self.query = query
  }
}
