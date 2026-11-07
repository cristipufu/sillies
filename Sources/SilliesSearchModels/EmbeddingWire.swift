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
  case embed(SearchEmbeddingInput)
  case advanceVaultIndex(URL)
  case searchVaultIndex(VaultVectorQuery)
  var isInteractive: Bool {
    switch self {
    case .searchVaultIndex: true
    case .embed(let input): input.purpose == .query
    case .prepare, .advanceVaultIndex: false
    }
  }
  var isPreparation: Bool { if case .prepare = self { true } else { false } }
}
package struct EmbeddingResponse: Codable, Sendable {
  package var identity: String?
  package var embedding: SearchEmbedding?
  package var failure: String?
  package var indexHasMore: Bool?
  package var passageIDs: [Int64]?
  package init(
    identity: String? = nil, embedding: SearchEmbedding? = nil, failure: String? = nil,
    indexHasMore: Bool? = nil, passageIDs: [Int64]? = nil
  ) {
    self.identity = identity
    self.embedding = embedding
    self.failure = failure
    self.indexHasMore = indexHasMore
    self.passageIDs = passageIDs
  }
}
