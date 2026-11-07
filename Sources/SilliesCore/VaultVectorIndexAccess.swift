import Foundation

/// An optional acceleration capability. Persistence and Vault do not import the native index SDK.
public struct VaultVectorIndexAccess: Sendable {
  public let advance: @Sendable (URL) async throws -> Bool
  public let search: @Sendable (VaultVectorQuery) async throws -> [Int64]?
  public init(
    advance: @escaping @Sendable (URL) async throws -> Bool,
    search: @escaping @Sendable (VaultVectorQuery) async throws -> [Int64]?
  ) {
    self.advance = advance
    self.search = search
  }
}
