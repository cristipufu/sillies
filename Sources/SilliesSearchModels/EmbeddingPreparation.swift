import Foundation
import SilliesCore

/// Providers decide whether an input fits; this owner preserves and combines all accepted windows.
/// No token estimate, truncated prefix, or partial result can stand in for the complete input.
package enum EmbeddingPreparation {
  package static let revision = "bounded-mean-v1"
  package static let maximumInputBytes = 8_192
  private static let maximumChunkAttempts = 128

  package static func embed(
    _ input: SearchEmbeddingInput,
    encode: @Sendable (SearchEmbeddingInput) async throws -> EmbeddingChunkResult
  ) async throws -> SearchEmbedding? {
    guard !input.text.isEmpty, input.text.utf8.count <= maximumInputBytes else {
      throw SearchEmbeddingError.unavailable
    }
    var pending = [input.text]
    var mean = WeightedMean()
    var attempts = 0
    while let text = pending.popLast() {
      try Task.checkCancellation()
      // A refusal to fit within bounded work is an unsupported input, not a failed index job.
      guard attempts < maximumChunkAttempts else { return nil }
      attempts += 1
      let result = try await encode(.init(text: text, purpose: input.purpose))
      try Task.checkCancellation()
      switch result {
      case .embedded(let chunk): try mean.include(chunk)
      case .unsupported: return nil
      case .exceedsCapacity:
        guard let parts = split(text) else { return nil }
        pending.append(parts.suffix)
        pending.append(parts.prefix)
      }
    }
    return try mean.embedding()
  }

  private static func split(_ text: String) -> (prefix: String, suffix: String)? {
    let count = text.count
    guard count > 1 else { return nil }
    let middle = text.index(text.startIndex, offsetBy: count / 2)
    let earliest = text.index(text.startIndex, offsetBy: count / 4)
    let boundary: String.Index
    if let space = text[..<middle].lastIndex(where: \.isWhitespace), space >= earliest {
      boundary = text.index(after: space)
    } else {
      boundary = middle
    }
    return (String(text[..<boundary]), String(text[boundary...]))
  }

  private struct WeightedMean {
    private var space: String?
    private var sum: [Double] = []
    private var tokens = 0

    mutating func include(_ chunk: EmbeddingChunk) throws {
      if space == nil {
        space = chunk.space
        sum = Array(repeating: 0, count: chunk.mean.count)
      }
      guard space == chunk.space, sum.count == chunk.mean.count else {
        throw SearchEmbeddingError.invalidVector
      }
      for index in sum.indices {
        sum[index] += Double(chunk.mean[index]) * Double(chunk.tokenCount)
      }
      tokens += chunk.tokenCount
    }

    func embedding() throws -> SearchEmbedding? {
      guard let space, tokens > 0 else { return nil }
      return try SearchEmbedding(space: space, values: sum.map { Float($0 / Double(tokens)) })
    }
  }
}
