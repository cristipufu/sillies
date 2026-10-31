import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

/// Opt-in documentation artwork. No desktop capture, live preferences, or microphone access.
@Test @MainActor func exportReadmePreviewCandidates() throws {
  guard let path = ProcessInfo.processInfo.environment["SILLIES_README_PREVIEWS"] else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let characters = try CharacterCatalog().characters
  for scheme in [ColorScheme.light, .dark] {
    let name = scheme == .light ? "skills-light" : "skills-dark"
    try ReadmePreviewRenderer.export(
      ReadmeSkillScene(characters: characters).environment(\.colorScheme, scheme),
      to: directory.appendingPathComponent("\(name).png"),
      appearance: scheme == .light ? .aqua : .darkAqua)
  }
  try ReadmePreviewRenderer.export(
    ReadmeCrewScene(characters: characters).environment(\.colorScheme, .light),
    to: directory.appendingPathComponent("crew.png"), appearance: .aqua)
  try ReadmePreviewRenderer.export(
    ReadmeListeningScene().environment(\.colorScheme, .light),
    to: directory.appendingPathComponent("listening-light.png"), appearance: .aqua)
}

@MainActor
private enum ReadmePreviewRenderer {
  private static let size = CGSize(width: 1200, height: 800)
  private static let scale: CGFloat = 2

  static func export(_ scene: some View, to destination: URL, appearance: NSAppearance.Name) throws
  {
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    defer { window.close() }
    let host = NSHostingView(
      rootView: scene.frame(width: size.width, height: size.height)
        .environment(\.controlActiveState, .active))
    host.sizingOptions = []
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ))
    bitmap.size = size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: destination, options: .atomic)
  }
}
