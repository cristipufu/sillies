import AppKit

/// Opt-in snapshots of fixture windows only, shared by native window/localization checks.
@MainActor enum AppWindowSnapshot {
  static func save(_ window: NSWindow, index: Int) async throws {
    guard let folder = ProcessInfo.processInfo.environment["SILLIES_WINDOW_SNAPSHOTS"],
      !folder.isEmpty, let view = window.contentView
    else { return }
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw CocoaError(.coderInvalidValue)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.coderInvalidValue)
    }
    let language = Bundle.main.preferredLocalizations.first ?? "en"
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    let file = directory.appendingPathComponent("\(language)-window-\(index).png")
    try await Task.detached(priority: .utility) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
    }.value
    print("NATIVE LOCALIZATION SNAPSHOT: \(language) · \(window.title)")
  }
}
