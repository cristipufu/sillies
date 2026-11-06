import AppKit
import ImageIO
import QuartzCore
import SilliesCore
import Testing
import UniformTypeIdentifiers

@testable import SilliesApp

/// Offscreen artwork review only: no windows are ordered and no desktop pixels are captured.
@Test @MainActor func exportNewCompanionArtwork() throws {
  guard let path = ProcessInfo.processInfo.environment["SILLIES_COMPANION_PREVIEWS"] else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let animations = AnimationLibrary()
  for character in NewCompanionFixture.all {
    let rig = try #require(RendererRegistry().make(character.renderer))
    for (name, pose) in [
      ("standing", AttachmentPose.standing), ("left", .hangingLeft), ("right", .hangingRight),
    ] {
      rig.setAttachmentPose(pose)
      rig.resetPose()
      try CompanionArtworkExport.png(
        rig, to: directory.appendingPathComponent("\(character.id)-\(name).png"))
    }
    rig.setAttachmentPose(.standing)
    for clip in [character.signature, character.flourish, .walk, .listen, "scene.dance"] {
      animations.apply(
        .init(animation: clip), to: rig, characterID: character.id, reducedMotion: false)
      try CompanionArtworkExport.movie(
        rig, to: directory.appendingPathComponent("\(character.id)-\(clip.rawValue).gif"))
    }
  }
}

@MainActor
private enum CompanionArtworkExport {
  private static let pixels = 384
  private static let frameRate = 24
  private static let duration = 4
  private static let designPadding: CGFloat = 16
  private static let canvasSize: CGFloat = 160

  static func png(_ rig: CharacterRig, to destination: URL) throws {
    let image = try bitmap(rig)
    let data = try #require(image.representation(using: .png, properties: [:]))
    try data.write(to: destination, options: .atomic)
  }

  static func movie(_ rig: CharacterRig, to url: URL) throws {
    let destination = try #require(
      CGImageDestinationCreateWithURL(
        url as CFURL, UTType.gif.identifier as CFString, duration * frameRate, nil))
    CGImageDestinationSetProperties(
      destination,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let clock = try OffscreenClipSampler(root: rig.root)
    defer { clock.restore() }
    for frame in 0..<(duration * frameRate) {
      clock.sample(at: Double(frame) / Double(frameRate))
      let image = try #require(try bitmap(rig).cgImage)
      CGImageDestinationAddImage(
        destination, image,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(frameRate)]]
          as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    try contactSheet(
      rig, clock: clock, to: url.deletingPathExtension().appendingPathExtension("png"))
  }

  private static func contactSheet(_ rig: CharacterRig, clock: OffscreenClipSampler, to url: URL)
    throws
  {
    let times = [0.0, 0.55, 1.1, 1.65, 2.2, 2.75]
    let sheet = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels * times.count,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: sheet)).cgContext
    for (index, time) in times.enumerated() {
      clock.sample(at: time)
      let frame = try #require(try bitmap(rig).cgImage)
      context.draw(frame, in: CGRect(x: index * pixels, y: 0, width: pixels, height: pixels))
    }
    let data = try #require(sheet.representation(using: .png, properties: [:]))
    try data.write(to: url, options: .atomic)
  }

  private static func bitmap(_ rig: CharacterRig) throws -> NSBitmapImageRep {
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
    context.setFillColor(NSColor(hex: "FAF8F4").cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / canvasSize
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: designPadding, y: designPadding)
    rig.root.render(in: context)
    return bitmap
  }
}
