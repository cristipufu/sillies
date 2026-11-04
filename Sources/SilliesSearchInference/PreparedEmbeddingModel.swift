import SilliesCore

protocol PreparedEmbeddingModel: Sendable {
  var identity: String { get async }
  func embed(_ input: MemoryEmbeddingInput) async throws -> MemoryEmbedding?
}
