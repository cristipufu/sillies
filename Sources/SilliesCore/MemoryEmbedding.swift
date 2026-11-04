import Foundation

/// A vector is meaningful only inside its exact model, revision and language space.
public struct MemoryEmbedding: Codable, Equatable, Sendable {
  public static let maximumDimensions = 4096
  private static let maximumSpaceBytes = 1024
  public let space: String
  public let values: [Float]
  public init(space: String, values: [Float]) throws {
    guard !space.isEmpty, space.utf8.count <= Self.maximumSpaceBytes,
      !values.isEmpty, values.count <= Self.maximumDimensions, values.allSatisfy(\.isFinite)
    else { throw MemoryEmbeddingError.invalidVector }
    let length = sqrt(values.reduce(Double.zero) { $0 + Double($1) * Double($1) })
    guard length.isFinite, length > 0 else { throw MemoryEmbeddingError.invalidVector }
    self.space = space
    self.values = values.map { Float(Double($0) / length) }
  }
  public func similarity(to other: Self) -> Float? {
    guard space == other.space, values.count == other.values.count else { return nil }
    return zip(values, other.values).reduce(0) { $0 + $1.0 * $1.1 }
  }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      space: container.decode(String.self, forKey: .space),
      values: container.decode([Float].self, forKey: .values))
  }
}

public enum MemoryEmbeddingError: Error { case invalidVector, unavailable }

public struct MemoryEmbeddingInput: Codable, Sendable {
  public enum Purpose: String, Codable, Sendable { case query, passage }
  public let text: String
  public let purpose: Purpose
  public init(text: String, purpose: Purpose) {
    self.text = text
    self.purpose = purpose
  }
}

/// Injected capability. Native models and their lifetime never belong to the memory store.
public struct MemoryEmbeddingAccess: Sendable {
  public let identity: String
  public let embed: @Sendable (MemoryEmbeddingInput) async throws -> MemoryEmbedding?
  public init(
    identity: String,
    embed: @escaping @Sendable (MemoryEmbeddingInput) async throws -> MemoryEmbedding?
  ) {
    self.identity = identity
    self.embed = embed
  }
}

public struct MemoryIndexItem: Sendable {
  public let owner: String
  public let memory: CompanionMemory
  public init(owner: String, memory: CompanionMemory) {
    self.owner = owner
    self.memory = memory
  }
  public var text: String { memory.key + ": " + memory.value }
}

public struct MemoryIndexProgress: Equatable, Sendable {
  public let processed: Int
  public let searchable: Int
  public let total: Int
  public init(processed: Int, searchable: Int, total: Int) {
    self.processed = processed
    self.searchable = searchable
    self.total = total
  }
}
