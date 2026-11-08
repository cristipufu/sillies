import SilliesCore

/// A provider's unnormalized mean and actual token count, before combining complete input windows.
package struct EmbeddingChunk: Sendable {
  package let space: String
  package let mean: [Float]
  package let tokenCount: Int

  package init(space: String, mean: [Float], tokenCount: Int) throws {
    guard (1...EmbeddingPreparation.maximumInputBytes).contains(tokenCount) else {
      throw SearchEmbeddingError.invalidVector
    }
    _ = try SearchEmbedding(space: space, values: mean)
    self.space = space
    self.mean = mean
    self.tokenCount = tokenCount
  }
}

package enum EmbeddingChunkResult: Sendable {
  case embedded(EmbeddingChunk)
  case exceedsCapacity
  case unsupported
}
