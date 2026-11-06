import Foundation

/// A vector is meaningful only inside its exact model, revision and language space.
public struct SearchEmbedding: Codable, Equatable, Sendable {
  public static let maximumDimensions = 4096
  private static let maximumSpaceBytes = 1024
  public let space: String
  public let values: [Float]
  public init(space: String, values: [Float]) throws {
    guard !space.isEmpty, space.utf8.count <= Self.maximumSpaceBytes,
      !values.isEmpty, values.count <= Self.maximumDimensions, values.allSatisfy(\.isFinite)
    else { throw SearchEmbeddingError.invalidVector }
    let length = sqrt(values.reduce(Double.zero) { $0 + Double($1) * Double($1) })
    guard length.isFinite, length > 0 else { throw SearchEmbeddingError.invalidVector }
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
