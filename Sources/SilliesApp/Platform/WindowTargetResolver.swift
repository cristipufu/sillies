import AppKit
import CoreGraphics
import SilliesCore

/// Single-window metadata reads. Call from a worker, never from mouse handling or view rendering.
enum WindowTargetResolver {
  private static let minimumVisibleAlpha: Double = 0.05

  static func candidate(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetCandidate? {
    guard let entry = windowEntry(for: windowID),
      (entry[kCGWindowLayer as String] as? Int) == 0,
      (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
      (entry[kCGWindowAlpha as String] as? Double ?? 1) > minimumVisibleAlpha,
      let pid = entry[kCGWindowOwnerPID as String] as? Int32,
      let bounds = entry[kCGWindowBounds as String] as? [String: Any],
      let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
    else { return nil }
    let minimum = PointerWindowGesture.defaultMinimumWindowSize
    guard cgFrame.width >= minimum.width, cgFrame.height >= minimum.height else { return nil }
    let app = NSRunningApplication(processIdentifier: pid)
    return WindowTargetCandidate(
      windowID: windowID, processID: pid,
      appName: app?.localizedName ?? (entry[kCGWindowOwnerName as String] as? String) ?? "App",
      bundleIdentifier: app?.bundleIdentifier,
      windowTitle: entry[kCGWindowName as String] as? String,
      frame: ScreenCoordinates.appKitRect(
        fromAccessibility: cgFrame, primaryScreenTop: primaryScreenTop))
  }

  static func currentSnapshot(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> (frame: CGRect, title: String?)? {
    guard let entry = windowEntry(for: windowID),
      (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
      (entry[kCGWindowAlpha as String] as? Double ?? 1) > minimumVisibleAlpha,
      let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
      let cgFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { return nil }
    let frame = ScreenCoordinates.appKitRect(
      fromAccessibility: cgFrame, primaryScreenTop: primaryScreenTop)
    let title = entry[kCGWindowName as String] as? String
    return (frame, title)
  }

  private static func windowEntry(for windowID: CGWindowID) -> [String: Any]? {
    let list =
      CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
    return list?.first
  }
}

final class WindowTargetMetadata: Sendable {
  typealias Read = @Sendable (CGWindowID, Double) -> WindowTargetCandidate?
  static let shared = WindowTargetMetadata()
  private let queue = DispatchQueue(label: "app.sillies.drag-target-metadata", qos: .userInitiated)
  private let read: Read

  init(read: @escaping Read = { WindowTargetResolver.candidate(for: $0, primaryScreenTop: $1) }) {
    self.read = read
  }

  func candidate(for windowID: CGWindowID, primaryScreenTop: Double) async -> WindowTargetCandidate?
  {
    guard !Task.isCancelled else { return nil }
    let read = read
    return await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: read(windowID, primaryScreenTop))
      }
    }
  }

  func regions(primaryScreenTop: Double) async -> [DragWindowRegion] {
    guard !Task.isCancelled else { return [] }
    return await withCheckedContinuation { continuation in
      queue.async {
        let entries =
          CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
          ?? []
        let minimum = PointerWindowGesture.defaultMinimumWindowSize
        let regions = entries.prefix(256).compactMap { entry -> DragWindowRegion? in
          guard (entry[kCGWindowLayer as String] as? Int) == 0,
            (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
            let id = entry[kCGWindowNumber as String] as? UInt32,
            let bounds = entry[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
            frame.width >= minimum.width, frame.height >= minimum.height
          else { return nil }
          return DragWindowRegion(
            windowID: id,
            frame: ScreenCoordinates.appKitRect(
              fromAccessibility: frame, primaryScreenTop: primaryScreenTop))
        }
        continuation.resume(returning: regions)
      }
    }
  }
}
