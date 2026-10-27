import CoreGraphics

/// Rectangle coverage in a shared coordinate system; independent of AppKit and polling.
public enum WindowCoverage {
  public static func hasVisibleArea(in frame: CGRect, behind occluders: [CGRect]) -> Bool {
    guard !frame.isEmpty, !frame.isNull else { return false }
    let covers = occluders.map { frame.intersection($0) }.filter { !$0.isEmpty && !$0.isNull }
    let edges = Set([frame.minX, frame.maxX] + covers.flatMap { [$0.minX, $0.maxX] }).sorted()
    for (left, right) in zip(edges, edges.dropFirst()) where right > left {
      let intervals = covers.filter { $0.minX <= left && $0.maxX >= right }
        .sorted { $0.minY < $1.minY }
      var coveredTo = frame.minY
      for cover in intervals {
        if cover.minY > coveredTo { return true }
        coveredTo = max(coveredTo, cover.maxY)
      }
      if coveredTo < frame.maxY { return true }
    }
    return false
  }
}
