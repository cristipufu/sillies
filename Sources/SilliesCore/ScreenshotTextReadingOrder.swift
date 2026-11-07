import CoreGraphics

/// Recursive whitespace cuts keep independent columns out of the same reading row.
struct ScreenshotTextReadingOrder {
  struct Metrics {
    let characterWidth: CGFloat
    let lineHeight: CGFloat
    private static let paragraphGapInLineHeights: CGFloat = 0.8
    var paragraphGap: CGFloat { lineHeight * Self.paragraphGapInLineHeights }
  }
  let rectangles: [CGRect]
  let metrics: Metrics
  private static let maximumDepth = 24
  private static let columnGapInCharacters: CGFloat = 3

  func regions(direction: ScreenshotTextLayout.WritingDirection) -> [[Int]] {
    partition(Array(rectangles.indices), direction: direction, depth: 0)
  }

  private func partition(
    _ indices: [Int], direction: ScreenshotTextLayout.WritingDirection, depth: Int
  ) -> [[Int]] {
    guard indices.count > 1, depth < Self.maximumDepth else { return [indices] }
    if let split = columnSplit(indices) {
      let children = direction == .leftToRight ? [split.0, split.1] : [split.1, split.0]
      return children.flatMap { partition($0, direction: direction, depth: depth + 1) }
    }
    if let split = paragraphSplit(indices) {
      return [split.0, split.1].flatMap { partition($0, direction: direction, depth: depth + 1) }
    }
    return [indices]
  }

  private func columnSplit(_ indices: [Int]) -> ([Int], [Int])? {
    let sorted = indices.sorted { rectangles[$0].minX < rectangles[$1].minX }
    guard let first = sorted.first else { return nil }
    var right = rectangles[first].maxX
    var widest: (width: CGFloat, position: Int)?
    for position in 1..<sorted.count {
      let rectangle = rectangles[sorted[position]]
      let gap = rectangle.minX - right
      if gap > metrics.characterWidth * Self.columnGapInCharacters,
        gap > (widest?.width ?? 0), spansRows(Array(sorted[..<position])),
        spansRows(Array(sorted[position...]))
      {
        widest = (gap, position)
      }
      right = max(right, rectangle.maxX)
    }
    guard let widest else { return nil }
    return (Array(sorted[..<widest.position]), Array(sorted[widest.position...]))
  }

  private func spansRows(_ indices: [Int]) -> Bool {
    let centers = indices.map { rectangles[$0].midY }
    guard let top = centers.max(), let bottom = centers.min() else { return false }
    return top - bottom >= metrics.lineHeight && top > bottom
  }

  private func paragraphSplit(_ indices: [Int]) -> ([Int], [Int])? {
    let sorted = indices.sorted { rectangles[$0].maxY > rectangles[$1].maxY }
    guard let first = sorted.first else { return nil }
    var bottom = rectangles[first].minY
    var widest: (height: CGFloat, position: Int)?
    for position in 1..<sorted.count {
      let rectangle = rectangles[sorted[position]]
      let gap = bottom - rectangle.maxY
      if gap > metrics.paragraphGap, gap > (widest?.height ?? 0) {
        widest = (gap, position)
      }
      bottom = min(bottom, rectangle.minY)
    }
    guard let widest else { return nil }
    return (Array(sorted[..<widest.position]), Array(sorted[widest.position...]))
  }
}
