import Foundation

/// Paragraph edits retain native text layout for the unchanged middle of a rolling transcript.
public struct TranscriptTextChanges: Sendable {
  public struct Edit: Sendable {
    public let utf16Range: Range<Int>
    public let replacement: String
  }

  private struct Paragraph {
    let text: String
    let utf16Range: Range<Int>
  }

  /// Apply in order: each UTF-16 range addresses the result of the preceding edits.
  public let edits: [Edit]

  public init(replacing previous: String, with current: String) {
    let before = Self.paragraphs(in: previous)
    let after = Self.paragraphs(in: current)
    let changes = after.difference(from: before) { $0.text.utf8.elementsEqual($1.text.utf8) }
    edits = Self.removals(changes, paragraphs: before) + Self.insertions(changes, paragraphs: after)
  }

  private static func paragraphs(in text: String) -> [Paragraph] {
    let lines = text.components(separatedBy: "\n")
    var offset = 0
    var paragraphs: [Paragraph] = []
    for (index, line) in lines.enumerated() {
      let content = index == lines.count - 1 ? line : line + "\n"
      let end = offset + content.utf16.count
      paragraphs.append(Paragraph(text: content, utf16Range: offset..<end))
      offset = end
    }
    return paragraphs
  }

  private static func removals(
    _ changes: CollectionDifference<Paragraph>, paragraphs: [Paragraph]
  ) -> [Edit] {
    let offsets = changes.removals.compactMap { change -> Int? in
      guard case .remove(let offset, _, _) = change else { return nil }
      return offset
    }
    return offsets.sorted(by: >).map {
      Edit(utf16Range: paragraphs[$0].utf16Range, replacement: "")
    }
  }

  private static func insertions(
    _ changes: CollectionDifference<Paragraph>, paragraphs: [Paragraph]
  ) -> [Edit] {
    let offsets = changes.insertions.compactMap { change -> Int? in
      guard case .insert(let offset, _, _) = change else { return nil }
      return offset
    }
    return offsets.sorted().map {
      let paragraph = paragraphs[$0]
      let start = paragraph.utf16Range.lowerBound
      return Edit(utf16Range: start..<start, replacement: paragraph.text)
    }
  }
}
