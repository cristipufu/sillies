import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test(arguments: [1, 3, 4, 5, 7, 384, 4096])
func storedVectorSimilarityMatchesScalarOracleWithUnalignedBytes(_ dimensions: Int) throws {
  let values = (0..<dimensions).map { Float($0 % 7 - 3) / 5 }
  let queryValues = (0..<dimensions).map { Float($0 % 11 - 5) / 7 }
  let embedding = try SearchEmbedding(space: "test", values: queryValues)
  let query = SearchVectorQuery(embedding)
  var data = Data([0])
  data.append(SearchVectorStorage.encode(values))
  let actual = try data.withUnsafeBytes { bytes in
    try query.similarity(.init(rebasing: bytes.dropFirst()))
  }
  let dot = zip(values, embedding.values).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
  let norm = sqrt(values.reduce(0.0) { $0 + Double($1) * Double($1) })
  #expect(abs(Double(actual) - dot / norm) < 0.000_001)
}

@Test(arguments: [Float.nan, Float.infinity, -Float.infinity, Float.zero])
func storedVectorSimilarityRejectsNonfiniteAndZeroNormRows(_ value: Float) throws {
  let query = SearchVectorQuery(try .init(space: "test", values: [1, 0, 0, 0, 0]))
  // Cover corruption in both a full vector block and its scalar remainder.
  for offset in [0, 4] {
    var values = Array(repeating: Float.zero, count: 5)
    values[offset] = value
    let data = SearchVectorStorage.encode(values)
    #expect(throws: ConversationStorageError.self) {
      try data.withUnsafeBytes { try query.similarity($0) }
    }
  }
}

@Test func storedVectorSimilarityRejectsTruncatedAndMismatchedRows() throws {
  let query = SearchVectorQuery(try .init(space: "test", values: [1, 0, 0, 0]))
  for count in [0, 1, 15, 17, 20] {
    let data = Data(repeating: 0, count: count)
    #expect(throws: ConversationStorageError.self) {
      try data.withUnsafeBytes { try query.similarity($0) }
    }
  }
}
