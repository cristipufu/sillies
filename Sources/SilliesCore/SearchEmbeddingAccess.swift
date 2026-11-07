import Foundation

public struct SearchEmbeddingAccess: Sendable {
  public let identity: String
  public let embed: @Sendable (SearchEmbeddingInput) async throws -> SearchEmbedding?
  public let vectorIndex: VaultVectorIndexAccess?
  public init(
    identity: String,
    vectorIndex: VaultVectorIndexAccess? = nil,
    embed: @escaping @Sendable (SearchEmbeddingInput) async throws -> SearchEmbedding?
  ) {
    self.identity = identity
    self.vectorIndex = vectorIndex
    self.embed = embed
  }
}
