import Foundation

/// Reviewed native sampling defaults. Task styles provide fallback values when a model has no preset.
public struct TextModelSampling: Codable, Equatable, Sendable {
  public let temperature: Float
  public let topP: Float
  public let topK: Int
  public let repetitionPenalty: Float

  public var isValid: Bool {
    (0...2).contains(temperature) && (0...1).contains(topP) && topP > 0
      && (0...Self.maximumTopK).contains(topK) && (1...2).contains(repetitionPenalty)
  }

  private static let maximumTopK = 1_000
}
