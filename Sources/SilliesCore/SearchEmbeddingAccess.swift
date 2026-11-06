import Foundation

public struct SearchEmbeddingAccess: Sendable {
  public let identity: String
  public let embed: @Sendable (SearchEmbeddingInput) async throws -> SearchEmbedding?
  public init(
    identity: String,
    embed: @escaping @Sendable (SearchEmbeddingInput) async throws -> SearchEmbedding?
  ) {
    self.identity = identity
    self.embed = embed
  }
}
