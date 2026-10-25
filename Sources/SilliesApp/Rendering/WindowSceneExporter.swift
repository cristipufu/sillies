import AppKit

/// Renders only Sillies-owned views and their actual tracked positions. No desktop capture.
@MainActor
enum WindowSceneExporter {
  static func export(window: NSWindow, companions: [(NSView, CGRect)], to url: URL) throws {
    let canvas = window.frame.insetBy(dx: -120, dy: -110)
    let scale = 2.0
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale),
        pixelsHigh: Int(canvas.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return }
    // Capture views before installing the destination graphics context.
    let windowView = window.contentView?.superview ?? window.contentView
    let windowImage = windowView.flatMap(snapshot)
    let pets = companions.compactMap { view, frame in snapshot(view).map { ($0, frame) } }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    NSColor(hex: "EEEAF2").setFill()
    NSRect(origin: .zero, size: canvas.size).fill()
    if let windowImage {
      windowImage.draw(in: window.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY))
    }
    for (image, frame) in pets {
      image.draw(in: frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY))
    }
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
  }

  private static func snapshot(_ view: NSView) -> NSImage? {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let image = bitmap.cgImage else { return nil }
    return NSImage(cgImage: image, size: view.bounds.size)
  }
}
