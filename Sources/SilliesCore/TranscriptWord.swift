import Foundation

/// Recognized text with audio timing and an explicit word or subword boundary.
public struct TranscriptWord: Sendable, Equatable {
  public enum Boundary: Sendable { case separated, attached }
  public let text: String
  public let start: TimeInterval
  public let end: TimeInterval
  public let boundary: Boundary
  public init(
    text: String, start: TimeInterval, end: TimeInterval, boundary: Boundary = .separated
  ) {
    self.text = text
    self.start = start
    self.end = end
    self.boundary = boundary
  }

  public static func renderedText(_ words: [Self]) -> String {
    words.reduce(into: "") { text, word in
      if !text.isEmpty, word.boundary == .separated { text += " " }
      text += word.text
    }.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
