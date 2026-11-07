import Foundation

public struct VaultVectorQuery: Codable, Sendable {
  public let directory: URL
  public let embedding: SearchEmbedding
  public let limit: Int
  public init(directory: URL, embedding: SearchEmbedding, limit: Int) {
    self.directory = directory
    self.embedding = embedding
    self.limit = max(1, min(256, limit))
  }
}
