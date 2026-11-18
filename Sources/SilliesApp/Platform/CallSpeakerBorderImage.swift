import CoreGraphics
import SilliesCore

/// The bitmap is scoped to this calculation; only border sample colors leave its buffer.
enum CallSpeakerBorderImage {
  private static let bytesPerPixel = 4
  private static let bitsPerComponent = 8
  private enum Channel: Int { case red, green, blue }

  static func speakers(
    in image: CGImage, layout: CallSpeakerVisualLayout, style: CallSpeakerBorder.Style
  )
    -> [CallSpeakerName]?
  {
    guard image.width == Int(layout.crop.width), image.height == Int(layout.crop.height),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: bitsPerComponent,
        bytesPerRow: image.width * bytesPerPixel, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue),
      let data = context.data
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = data.bindMemory(
      to: UInt8.self, capacity: image.width * image.height * bytesPerPixel)
    let highlighted = withExtendedLifetime(context) {
      layout.tiles.filter { tile in
        CallSpeakerBorder.isHighlighted(frame: layout.imageFrame(for: tile), style: style) {
          point in
          guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
            point.x < CGFloat(image.width), point.y < CGFloat(image.height)
          else { return nil }
          let offset = (Int(point.y) * image.width + Int(point.x)) * bytesPerPixel
          return .init(
            red: pixels[offset + Channel.red.rawValue],
            green: pixels[offset + Channel.green.rawValue],
            blue: pixels[offset + Channel.blue.rawValue])
        }
      }
    }
    // A stale muted highlight or simultaneous highlights cannot identify a remote audio passage.
    guard highlighted.count == 1, let tile = highlighted.first, tile.audio == .unmuted else {
      return []
    }
    return [tile.name]
  }
}
