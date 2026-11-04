import Foundation
import SilliesCore
import SilliesSearchModels

actor SearchEmbeddingRuntime {
  private static let maximumInputBytes = 8192
  private var configuration: EmbeddingConfiguration?
  private var model: (any PreparedEmbeddingModel)?

  func respond(to request: EmbeddingRequest) async throws -> EmbeddingResponse {
    switch request {
    case .prepare(let configuration):
      guard self.configuration == nil || self.configuration == configuration else {
        throw MemoryEmbeddingError.unavailable
      }
      if model == nil { model = try await EmbeddingRuntimeFactory.prepare(configuration) }
      self.configuration = configuration
      return await .init(identity: model?.identity)
    case .embed(let input):
      guard !input.text.isEmpty, input.text.utf8.count <= Self.maximumInputBytes, let model else {
        throw MemoryEmbeddingError.unavailable
      }
      return try await .init(embedding: model.embed(input))
    }
  }
}
