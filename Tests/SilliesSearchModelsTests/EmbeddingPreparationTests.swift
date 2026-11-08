import Foundation
import SilliesCore
import Testing

@testable import SilliesSearchModels

@Test func embeddingPreparationPreservesEveryCharacterAndPurposeAcrossCapacitySplits() async throws
{
  let input = SearchEmbeddingInput(
    text: "Dimineață bună! 你好世界. Alpha\nbeta café 🐸.", purpose: .passage)
  let recorder = AcceptedEmbeddingInputs()
  let result = try await EmbeddingPreparation.embed(input) { part in
    if part.text.utf8.count > 14 { return .exceedsCapacity }
    await recorder.append(part)
    return try .embedded(.init(space: "fixture", mean: [2, 1], tokenCount: part.text.utf8.count))
  }
  let accepted = await recorder.inputs
  #expect(accepted.count > 1)
  #expect(accepted.map(\.text).joined() == input.text)
  #expect(accepted.allSatisfy { $0.purpose == input.purpose })
  #expect(try #require(result).space == "fixture")
}

@Test func embeddingPreparationWeightsUnnormalizedMeansByActualTokenCount() async throws {
  let result = try await EmbeddingPreparation.embed(.init(text: "ab", purpose: .query)) { part in
    switch part.text {
    case "ab": return .exceedsCapacity
    case "a": return try .embedded(.init(space: "fixture", mean: [2, 0], tokenCount: 3))
    default: return try .embedded(.init(space: "fixture", mean: [0, 8], tokenCount: 1))
    }
  }
  let values = try #require(result).values
  #expect(abs(values[0] - 0.6) < 0.00001)
  #expect(abs(values[1] - 0.8) < 0.00001)
}

@Test func embeddingPreparationNeverReturnsOnlyTheSupportedPrefix() async throws {
  let result = try await EmbeddingPreparation.embed(.init(text: "ab", purpose: .passage)) { part in
    switch part.text {
    case "ab": return .exceedsCapacity
    case "a": return try .embedded(.init(space: "fixture", mean: [1], tokenCount: 1))
    default: return .unsupported
    }
  }
  #expect(result == nil)
  let indivisible = try await EmbeddingPreparation.embed(
    .init(text: "👨‍👩‍👧‍👦", purpose: .passage)
  ) { _ in .exceedsCapacity }
  #expect(indivisible == nil)
}

@Test func embeddingPreparationRejectsMixedSpacesAndBoundsProviderWork() async throws {
  await #expect(throws: SearchEmbeddingError.self) {
    try await EmbeddingPreparation.embed(.init(text: "ab", purpose: .passage)) { part in
      if part.text.count > 1 { return .exceedsCapacity }
      return try .embedded(.init(space: part.text, mean: [1], tokenCount: 1))
    }
  }
  let recorder = AcceptedEmbeddingInputs()
  let unsupported = try await EmbeddingPreparation.embed(
    .init(text: String(repeating: "a", count: 2_048), purpose: .passage)
  ) { part in
    await recorder.append(part)
    if part.text.count > 1 { return .exceedsCapacity }
    return try .embedded(.init(space: "fixture", mean: [1], tokenCount: 1))
  }
  #expect(unsupported == nil)
  #expect(await recorder.inputs.count <= 128)
}

@Test func embeddingPreparationDiscardsAProviderResultAfterCancellation() async throws {
  let task = Task {
    try await EmbeddingPreparation.embed(.init(text: "hello", purpose: .query)) { _ in
      withUnsafeCurrentTask { $0?.cancel() }
      return try .embedded(.init(space: "fixture", mean: [1], tokenCount: 1))
    }
  }
  await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func embeddingChunksRejectInvalidProviderValues() throws {
  #expect(throws: SearchEmbeddingError.self) {
    try EmbeddingChunk(space: "fixture", mean: [.nan], tokenCount: 1)
  }
  #expect(throws: SearchEmbeddingError.self) {
    try EmbeddingChunk(space: "fixture", mean: [1], tokenCount: Int.max)
  }
  #expect(throws: SearchEmbeddingError.self) {
    try EmbeddingChunk(space: "fixture", mean: [1], tokenCount: 0)
  }
}

private actor AcceptedEmbeddingInputs {
  private(set) var inputs: [SearchEmbeddingInput] = []
  func append(_ input: SearchEmbeddingInput) { inputs.append(input) }
}
