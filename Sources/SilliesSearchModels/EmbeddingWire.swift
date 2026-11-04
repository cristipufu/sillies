import Foundation
import SilliesCore

package struct EmbeddingConfiguration: Codable, Equatable, Sendable {
  package let provider: String
  package let identity: String
  package let directory: URL?
  package init(provider: String, identity: String, directory: URL? = nil) {
    self.provider = provider
    self.identity = identity
    self.directory = directory
  }
}
package enum EmbeddingRequest: Codable, Sendable {
  case prepare(EmbeddingConfiguration)
  case embed(MemoryEmbeddingInput)
}
package struct EmbeddingResponse: Codable, Sendable {
  package var identity: String?
  package var embedding: MemoryEmbedding?
  package var failure: String?
  package init(identity: String? = nil, embedding: MemoryEmbedding? = nil, failure: String? = nil) {
    self.identity = identity
    self.embedding = embedding
    self.failure = failure
  }
}
