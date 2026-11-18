import Foundation

/// Recognizes a thin, continuous speaking highlight, rather than green content inside a video.
public enum CallSpeakerBorder {
  public struct Color: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
      self.red = red
      self.green = green
      self.blue = blue
    }
  }
  public struct Style: Sendable {
    public let color: Color
    public let tolerance: UInt8
    public init(color: Color, tolerance: UInt8) {
      self.color = color
      self.tolerance = tolerance
    }
    fileprivate func matches(_ sample: Color) -> Bool {
      abs(Int(color.red) - Int(sample.red)) <= Int(tolerance)
        && abs(Int(color.green) - Int(sample.green)) <= Int(tolerance)
        && abs(Int(color.blue) - Int(sample.blue)) <= Int(tolerance)
    }
  }
  private enum Edge: CaseIterable { case top, bottom, left, right }
  private static let fractions: [CGFloat] = [0.2, 0.35, 0.5, 0.65, 0.8]
  private static let borderInset: CGFloat = 1.5
  private static let interiorInset: CGFloat = 6
  private static let minimumEdgeSamples = 4
  private static let minimumContrastingEdges = 3

  public static func isHighlighted(
    frame: CGRect, style: Style, colorAt: (CGPoint) -> Color?
  ) -> Bool {
    guard frame.width >= interiorInset * 2, frame.height >= interiorInset * 2,
      frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite
    else { return false }
    var contrastingEdges = 0
    for edge in Edge.allCases {
      var borderSamples = 0
      var contrastingSamples = 0
      for fraction in fractions {
        guard
          let border = colorAt(
            point(on: edge, frame: frame, fraction: fraction, inset: borderInset)),
          let interior = colorAt(
            point(on: edge, frame: frame, fraction: fraction, inset: interiorInset))
        else { return false }
        if style.matches(border) { borderSamples += 1 }
        if !style.matches(interior) { contrastingSamples += 1 }
      }
      guard borderSamples >= minimumEdgeSamples else { return false }
      if contrastingSamples >= minimumEdgeSamples { contrastingEdges += 1 }
    }
    return contrastingEdges >= minimumContrastingEdges
  }

  private static func point(on edge: Edge, frame: CGRect, fraction: CGFloat, inset: CGFloat)
    -> CGPoint
  {
    switch edge {
    case .top: CGPoint(x: frame.minX + frame.width * fraction, y: frame.minY + inset)
    case .bottom: CGPoint(x: frame.minX + frame.width * fraction, y: frame.maxY - inset)
    case .left: CGPoint(x: frame.minX + inset, y: frame.minY + frame.height * fraction)
    case .right: CGPoint(x: frame.maxX - inset, y: frame.minY + frame.height * fraction)
    }
  }
}
