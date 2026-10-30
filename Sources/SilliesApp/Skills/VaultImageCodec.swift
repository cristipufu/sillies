import AppKit
import ImageIO

/// Image conversion runs only on an I/O worker; views consume the prepared result.
enum VaultImageCodec {
  static let maxPreviewPixelDimension = 1280
  private static let bitsPerComponent = 8
  private static let bytesPerPixel = 4
  static func preparePreview(from cgImage: CGImage) -> CGImage {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let maxDimension = max(cgImage.width, cgImage.height)
    guard maxDimension > maxPreviewPixelDimension, maxDimension > 0 else { return cgImage }
    let scale = Double(maxPreviewPixelDimension) / Double(maxDimension)
    let targetWidth = max(1, Int((Double(cgImage.width) * scale).rounded()))
    let targetHeight = max(1, Int((Double(cgImage.height) * scale).rounded()))
    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: targetWidth * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return cgImage }
    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage() ?? cgImage
  }

  static func decodePreview(at url: URL) -> CGImage? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return autoreleasepool {
      let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
      guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary)
      else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPreviewPixelDimension,
      ]
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
  }

  static func encodePNGData(from cgImage: CGImage) -> Data? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return autoreleasepool {
      let rep = NSBitmapImageRep(cgImage: cgImage)
      return rep.representation(using: .png, properties: [:])
    }
  }

}
