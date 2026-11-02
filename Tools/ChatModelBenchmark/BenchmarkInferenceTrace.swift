import Foundation
import SilliesTextModels

/// Records synthetic inference rounds, including failed rounds, without retaining private reasoning.
actor BenchmarkInferenceTrace {
  private static let maximumGenerations = 64
  private var generations: [BenchmarkGeneration] = []

  func beginTurn() { generations.removeAll(keepingCapacity: true) }
  func record(_ generation: BenchmarkGeneration) throws {
    guard generations.count < Self.maximumGenerations else { throw Capacity.exceeded }
    generations.append(generation)
  }
  func snapshot() -> [BenchmarkGeneration] { generations }
  private enum Capacity: Error { case exceeded }
}
