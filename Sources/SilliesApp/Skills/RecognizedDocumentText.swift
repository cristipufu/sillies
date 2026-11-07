import Foundation
import NaturalLanguage
import SilliesCore
import Vision

/// Maps native document structure into the platform-independent whitespace formatter.
enum RecognizedDocumentText {
  static func render(_ observations: [DocumentObservation]) throws -> String {
    try observations.map { observation in
      try Task.checkCancellation()
      let document = observation.document
      let fragments = document.text.lines.compactMap(fragment)
      let tables = document.tables.map { table in
        ScreenshotTextLayout.Table(
          rows: table.rows.enumerated().map { rowIndex, row in
            row.enumerated().map { columnIndex, cell in
              // Merged cells appear in several rows/columns; retain their content once.
              cell.rowRange.lowerBound == rowIndex && cell.columnRange.lowerBound == columnIndex
                ? cell.content.text.transcript : ""
            }
          }, bounds: table.boundingRegion.boundingBox.cgRect)
      }
      let formatted = ScreenshotTextLayout.text(fragments: fragments, tables: tables)
      return formatted.isEmpty ? document.text.transcript : formatted
    }.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private static func fragment(_ observation: RecognizedTextObservation)
    -> ScreenshotTextLayout.Fragment?
  {
    guard let text = observation.topCandidates(1).first?.string else { return nil }
    let language = NLLanguageRecognizer.dominantLanguage(for: text)
    let direction = language.map { Locale.Language(identifier: $0.rawValue).characterDirection }
    return .init(
      text: text, bounds: observation.boundingBox.cgRect,
      direction: direction == .rightToLeft ? .rightToLeft : .leftToRight)
  }
}
