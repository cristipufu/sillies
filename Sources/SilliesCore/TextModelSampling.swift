import Foundation

/// Reviewed native sampling parameters, supplied independently for each task in a model profile.
public struct TextModelSampling: Codable, Equatable, Sendable {
  public let temperature: Float
  public let topP: Float
  public let topK: Int
  public let repetitionPenalty: Float?
  public init(temperature: Float, topP: Float, topK: Int, repetitionPenalty: Float?) {
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.repetitionPenalty = repetitionPenalty
  }

  public var isValid: Bool {
    (0...2).contains(temperature) && (0...1).contains(topP) && topP > 0
      && (0...Self.maximumTopK).contains(topK)
      && (repetitionPenalty.map { (1...2).contains($0) } ?? true)
  }

  private static let maximumTopK = 1_000
}
