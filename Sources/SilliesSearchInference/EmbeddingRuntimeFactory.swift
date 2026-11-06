import SilliesCore
import SilliesSearchModels

enum EmbeddingRuntimeFactory {
  static func prepare(_ configuration: EmbeddingConfiguration) async throws
    -> any PreparedEmbeddingModel
  {
    switch configuration.provider {
    case "apple": return AppleSearchEmbedding()
    case "e5":
      guard let directory = configuration.directory, directory.isFileURL else {
        throw SearchEmbeddingError.unavailable
      }
      return try await E5SearchEmbedding.load(
        directory: directory, identity: configuration.identity)
    default: throw SearchEmbeddingError.unavailable
    }
  }
}
