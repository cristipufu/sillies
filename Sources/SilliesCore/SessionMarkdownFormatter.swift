import Foundation

/// Owns the Markdown export contract independently of record construction and persistence.
public enum SessionMarkdownFormatter {
  public static func format(_ record: SessionRecord, locale: Locale = .current) -> String {
    let lines =
      metadata(record, locale: locale)
      + notes(record)
      + suggestions(record.suggestions)
      + section(
        "Action Items", text: record.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n"))
      + sourceMaterial(record)
    return lines.joined(separator: "\n")
  }

  private static func metadata(_ record: SessionRecord, locale: Locale) -> [String] {
    var lines = [
      "# \(record.displayTitle)",
      "- **Skill**: \(record.kind.title)",
      "- **Companion**: \(record.characterName)",
      "- **Date**: \(record.createdAt.ISO8601Format())",
    ]
    if record.durationSeconds >= 1 {
      lines.append("- **Duration**: \(SessionRecord.formatDuration(record.durationSeconds))")
    }
    if let language = record.languageIdentifier {
      lines.append(
        "- **Notes language**: \(locale.localizedString(forIdentifier: language) ?? language)")
    }
    return lines
  }

  private static func notes(_ record: SessionRecord) -> [String] {
    var lines = section("Summary", text: record.summary)
    if let failure = record.failureMessage { lines.append("\nSession issue: \(failure)") }
    if let filename = record.audioFilename { lines.append("\nAudio: \(filename)") }
    if !record.processingNote.isEmpty { lines.append("\n\(record.processingNote)") }
    return lines + section("Explanation", text: record.explanation)
  }

  private static func suggestions(_ values: [MeetingSuggestion]) -> [String] {
    let text = values.map {
      "- [\(SessionRecord.formatDuration($0.elapsed))] \($0.question)\n  Source: \($0.evidence)"
    }.joined(separator: "\n")
    return section("Meeting Suggestions", text: text)
  }

  private static func sourceMaterial(_ record: SessionRecord) -> [String] {
    let extracted = record.extractedText.isEmpty ? "" : "```\n\(record.extractedText)\n```"
    return section("Transcript", text: record.transcript)
      + section("Extracted Window Text", text: extracted)
      + section(
        "Stashed Items", text: record.stashedItems.map { "- \($0)" }.joined(separator: "\n"))
  }

  private static func section(_ title: String, text: String) -> [String] {
    text.isEmpty ? [] : ["\n## \(title)\n\(text)"]
  }
}
