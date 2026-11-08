import Foundation
import SilliesCore
import SilliesSearchModels
import SilliesVectorIndex

actor SearchEmbeddingRuntime {
  private var configuration: EmbeddingConfiguration?
  private var model: (any PreparedEmbeddingModel)?
  private let index = VaultVectorIndexRuntime()

  func respond(to request: EmbeddingRequest) async throws -> EmbeddingResponse {
    switch request {
    case .prepare(let configuration):
      guard self.configuration == nil || self.configuration == configuration else {
        throw SearchEmbeddingError.unavailable
      }
      if model == nil { model = try await EmbeddingRuntimeFactory.prepare(configuration) }
      self.configuration = configuration
      return await .init(identity: model?.identity)
    case .embed(let input):
      guard !input.text.isEmpty, input.text.utf8.count <= EmbeddingPreparation.maximumInputBytes,
        let model
      else {
        throw SearchEmbeddingError.unavailable
      }
      return try await .init(embedding: model.embed(input))
    case .advanceVaultIndex(let directory):
      guard let model else { throw SearchEmbeddingError.unavailable }
      return try await .init(
        indexHasMore: index.advance(directory: directory, provider: model.identity))
    case .searchVaultIndex(let query):
      guard let model else { throw SearchEmbeddingError.unavailable }
      return try await .init(passageIDs: index.search(query, provider: model.identity))
    }
  }
}
