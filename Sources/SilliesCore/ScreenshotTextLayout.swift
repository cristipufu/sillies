import CoreGraphics
import Foundation

/// Reassembles physical reading rows before restoring whitespace from OCR geometry.
public enum ScreenshotTextLayout {
  public enum WritingDirection: Sendable { case leftToRight, rightToLeft }

  public struct Fragment: Sendable {
    public let text: String
    public let bounds: CGRect
    public let direction: WritingDirection
    public init(text: String, bounds: CGRect, direction: WritingDirection = .leftToRight) {
      self.text = text
      self.bounds = bounds
      self.direction = direction
    }
  }
  public struct Table: Sendable {
    public let rows: [[String]]
    public let bounds: CGRect
    public init(rows: [[String]], bounds: CGRect) {
      self.rows = rows
      self.bounds = bounds
    }
  }
  private struct Block {
    let text: String
    let bounds: CGRect
  }
  private static let maximumIndentation = 40
  private static let maximumColumnPadding = 80
  private static let columnSeparator = "  "

  public static func text(fragments: [Fragment], tables: [Table] = []) -> String {
    let tables = tables.filter {
      !$0.rows.joined().allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    let fragments = fragments.filter { fragment in
      !fragment.text.isEmpty
        && !tables.contains {
          valid($0.bounds) && valid(fragment.bounds) && $0.bounds.contains(fragment.bounds)
        }
    }
    let positioned = fragments.filter { valid($0.bounds) }
    let positionedTables = tables.filter { valid($0.bounds) }
    let rectangles = positioned.map(\.bounds) + positionedTables.map(\.bounds)
    let metrics = ScreenshotTextReadingOrder.Metrics(
      characterWidth: median(positioned.map { $0.bounds.width / CGFloat(max(1, $0.text.count)) }),
      lineHeight: median(positioned.map { $0.bounds.height }))
    let order = ScreenshotTextReadingOrder(rectangles: rectangles, metrics: metrics)
    let regions = order.regions(direction: direction(of: positioned))
    let rendered = regions.map { indices in
      let text = indices.filter { $0 < positioned.count }.map { positioned[$0] }
      let tables = indices.filter { $0 >= positioned.count }.map {
        positionedTables[$0 - positioned.count]
      }
      return renderRegion(text, tables: tables, metrics: metrics)
    }
    let unpositioned =
      fragments.filter { !valid($0.bounds) }.map(\.text)
      + tables.filter { !valid($0.bounds) }.map { tableText($0.rows) }
    return (rendered + unpositioned).filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private static func renderRegion(
    _ fragments: [Fragment], tables: [Table], metrics: ScreenshotTextReadingOrder.Metrics
  ) -> String {
    let region = fragments.reduce(CGRect.null) { $0.union($1.bounds) }
    var blocks = physicalRows(fragments).compactMap {
      renderRow($0, within: region, metrics: metrics)
    }
    blocks += tables.map { Block(text: tableText($0.rows), bounds: $0.bounds) }
    blocks.sort { $0.bounds.maxY > $1.bounds.maxY }
    return renderBlocks(blocks, paragraphGap: metrics.paragraphGap)
  }

  private static func renderRow(
    _ row: [Fragment], within region: CGRect, metrics: ScreenshotTextReadingOrder.Metrics
  ) -> Block? {
    guard let first = row.first else { return nil }
    let bounds = row.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    let direction = direction(of: row)
    let ordered = row.sorted {
      direction == .leftToRight
        ? $0.bounds.minX < $1.bounds.minX : $0.bounds.maxX > $1.bounds.maxX
    }
    let offset = direction == .leftToRight ? bounds.minX - region.minX : region.maxX - bounds.maxX
    let indentation = indentation(offset: offset, characterWidth: metrics.characterWidth)
    return Block(
      text: String(repeating: " ", count: indentation) + ordered.map(\.text).joined(separator: " "),
      bounds: bounds)
  }

  private static func renderBlocks(_ blocks: [Block], paragraphGap: CGFloat) -> String {
    var result = ""
    var previous: Block?
    for block in blocks where !block.text.isEmpty {
      if let previous {
        let gap = previous.bounds.minY - block.bounds.maxY
        result += gap > paragraphGap ? "\n\n" : "\n"
      }
      result += block.text
      previous = block
    }
    return result
  }

  private static func physicalRows(_ fragments: [Fragment]) -> [[Fragment]] {
    let ordered = fragments.sorted {
      $0.bounds.maxY == $1.bounds.maxY
        ? $0.bounds.minX < $1.bounds.minX : $0.bounds.maxY > $1.bounds.maxY
    }
    var rows: [[Fragment]] = []
    for fragment in ordered {
      if let previous = rows.last?.first, sharesRow(previous.bounds, fragment.bounds) {
        rows[rows.count - 1].append(fragment)
      } else {
        rows.append([fragment])
      }
    }
    return rows
  }

  private static func sharesRow(_ first: CGRect, _ second: CGRect) -> Bool {
    let minimumOverlap: CGFloat = 0.5
    let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
    return overlap >= min(first.height, second.height) * minimumOverlap
      && abs(first.midY - second.midY) <= max(first.height, second.height) * minimumOverlap
  }

  private static func direction(of fragments: [Fragment]) -> WritingDirection {
    let balance = fragments.reduce(0) {
      $0 + ($1.direction == .leftToRight ? $1.text.count : -$1.text.count)
    }
    return balance >= 0 ? .leftToRight : .rightToLeft
  }

  private static func indentation(offset: CGFloat, characterWidth: CGFloat) -> Int {
    guard characterWidth > 0 else { return 0 }
    let spaces = (offset / characterWidth).rounded()
    guard spaces.isFinite else { return 0 }
    return Int(min(CGFloat(maximumIndentation), max(0, spaces)))
  }

  private static func tableText(_ rows: [[String]]) -> String {
    let rows = rows.map { $0.map { $0.components(separatedBy: .newlines).joined(separator: " ") } }
    let count = rows.map(\.count).max() ?? 0
    let widths = (0..<count).map { column in
      min(maximumColumnPadding, rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0)
    }
    return rows.map { row in
      row.enumerated().map { column, value in
        guard column < row.count - 1 else { return value }
        return value + String(repeating: " ", count: max(0, widths[column] - value.count))
      }.joined(separator: columnSeparator)
    }.joined(separator: "\n")
  }

  private static func valid(_ bounds: CGRect) -> Bool {
    bounds.minX.isFinite && bounds.minY.isFinite && bounds.maxX.isFinite && bounds.maxY.isFinite
      && bounds.width > 0 && bounds.height > 0
  }
  private static func median(_ values: [CGFloat]) -> CGFloat {
    let values = values.filter { $0.isFinite && $0 > 0 }.sorted()
    return values.isEmpty ? 0 : values[values.count / 2]
  }
}
