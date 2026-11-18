import Foundation

/// Only the union of verified participant tiles is eligible for transient visual inspection.
public struct CallSpeakerVisualLayout: Equatable, Sendable {
  public static let maximumTiles = 64
  public static let maximumDimension = 4_096
  public static let maximumPixels = 4_194_304
  private static let minimumTileDimension: CGFloat = 24
  private static let minimumTileCoverage: CGFloat = 0.75
  public let tiles: [CallSpeakerTile]
  public let crop: CGRect
  public let windowFrame: CGRect

  public init?(windowFrame: CGRect, tiles: [CallSpeakerTile]) {
    guard Self.isFinite(windowFrame), !tiles.isEmpty, tiles.count <= Self.maximumTiles,
      Set(tiles.map { $0.name.comparisonKey }).count == tiles.count,
      tiles.allSatisfy({
        Self.isFinite($0.frame) && windowFrame.contains($0.frame)
          && min($0.frame.width, $0.frame.height) >= Self.minimumTileDimension
      }), Self.areNonOverlapping(tiles)
    else { return nil }
    let bounds = tiles.reduce(CGRect.null) { $0.union($1.frame) }
    let crop = bounds.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY).integral
    let tileArea = tiles.reduce(CGFloat.zero) { $0 + $1.frame.width * $1.frame.height }
    guard crop.width <= CGFloat(Self.maximumDimension),
      crop.height <= CGFloat(Self.maximumDimension),
      crop.width * crop.height <= CGFloat(Self.maximumPixels),
      tileArea >= crop.width * crop.height * Self.minimumTileCoverage
    else { return nil }
    self.windowFrame = windowFrame
    self.tiles = tiles
    self.crop = crop
  }

  public func imageFrame(for tile: CallSpeakerTile) -> CGRect {
    tile.frame.offsetBy(dx: -windowFrame.minX - crop.minX, dy: -windowFrame.minY - crop.minY)
  }

  private static func isFinite(_ frame: CGRect) -> Bool {
    frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite
      && frame.width > 0 && frame.height > 0
  }

  private static func areNonOverlapping(_ tiles: [CallSpeakerTile]) -> Bool {
    for (index, tile) in tiles.enumerated() {
      for other in tiles.dropFirst(index + 1) {
        let intersection = tile.frame.intersection(other.frame)
        if !intersection.isNull, intersection.width > 0, intersection.height > 0 { return false }
      }
    }
    return true
  }
}
