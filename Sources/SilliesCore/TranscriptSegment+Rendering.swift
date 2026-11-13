import Foundation

extension TranscriptSegment {
  public var transcriptLine: String {
    line(speakerLabel: automaticSpeakerName?.transcriptLabel ?? speaker?.label)
  }
  public var originalTranscriptLine: String { line(speakerLabel: speaker?.label) }
  private func line(speakerLabel: String?) -> String {
    let label = speakerLabel.map { source + " · " + $0 } ?? source
    return "[\(SessionRecord.formatDuration(start))] \(label): \(text)"
  }
}
