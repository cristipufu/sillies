import AppKit
import QuartzCore

/// The same rounded fingers and sleeve palette are used on edges, ropes, and tools.
@MainActor
enum CharacterHandArtwork {
  static func draw(on layer: CALayer, at origin: CGPoint, rig: CharacterRig) {
    rig.pill(
      on: layer, CGRect(x: origin.x, y: origin.y, width: 13, height: 11),
      rig.gripFill, radius: 5, stroke: rig.gripOutline)
    for offset in [2.0, 5, 8] {
      rig.line(
        on: layer,
        points: [
          CGPoint(x: origin.x + 5, y: origin.y + offset),
          CGPoint(x: origin.x + 9, y: origin.y + offset),
        ],
        color: rig.gripOutline, width: 1)
    }
  }
}
