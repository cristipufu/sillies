import SilliesCore
import SilliesSearchModels

enum EmbeddingRuntimeFactory {
  static func prepare(_ configuration: EmbeddingConfiguration) async throws
    -> any PreparedEmbeddingModel
  {
    switch configuration.provider {
    case "apple": return AppleMemoryEmbedding()
    case "e5":
      guard let directory = configuration.directory, directory.isFileURL else {
        throw MemoryEmbeddingError.unavailable
      }
      return try await E5MemoryEmbedding.load(
        directory: directory, identity: configuration.identity)
    default: throw MemoryEmbeddingError.unavailable
    }
  }
}
