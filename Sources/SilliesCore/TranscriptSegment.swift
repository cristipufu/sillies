import Foundation

/// Structured source text survives formatting, dictation insertion, and speaker renaming.
public struct TranscriptSegment: Codable, Equatable, Sendable, Identifiable {
  public let sequence: Int
  public let source: String
  public let start: Double
  public let end: Double
  public let text: String
  public let speaker: TranscriptSpeaker?
  public var id: String { "\(source):\(sequence)" }

  public init(
    sequence: Int, source: String, start: Double, end: Double, text: String,
    speaker: TranscriptSpeaker? = nil
  ) {
    self.sequence = sequence
    self.source = source
    self.start = start
    self.end = end
    self.text = text
    self.speaker = speaker
  }
}
