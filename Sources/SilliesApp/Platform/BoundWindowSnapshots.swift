import CoreGraphics
import Foundation
import SilliesCore

/// Occlusion and existence are distinct reads. Only an exact-ID lookup can confirm closure.
enum BoundWindowSnapshots {
  struct Source {
    let visibleWindows: () -> [[String: Any]]?
    let targetWindows: (Set<CGWindowID>) -> [[String: Any]]?
    static var native: Source {
      Source(
        visibleWindows: {
          WindowMetadataReader.snapshot(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)?.entries
        }, targetWindows: { WindowMetadataReader.snapshot(for: $0)?.entries })
    }
  }
  private static let maximumInspectedWindows = 256
  private static let opaqueWindowAlpha = 0.99
  // System surfaces such as the Dock can have screen-sized transparent bounds and alpha == 1.
  // Their rectangles are not evidence that an application window is covered.
  private static let firstSystemOverlayLayer = Int(CGWindowLevelForKey(.dockWindow))

  static func read(
    windowIDs: Set<CGWindowID>, primaryScreenTop: Double,
    source: Source = .native
  ) -> [CGWindowID: WindowTargetSnapshot] {
    guard !windowIDs.isEmpty else { return [:] }
    guard let visible = source.visibleWindows() else {
      return unavailable(windowIDs)
    }
    var result = resolve(
      entries: visible, windowIDs: windowIDs, primaryScreenTop: primaryScreenTop)
    let missing = windowIDs.subtracting(result.keys)
    guard !missing.isEmpty else { return result }
    guard let known = source.targetWindows(missing) else {
      return result.merging(unavailable(missing)) { current, _ in current }
    }
    var complete = known.count <= min(missing.count, maximumInspectedWindows)
    for row in known.prefix(maximumInspectedWindows) {
      guard let entry = WindowServerSource.ParsedWindowEntry(dictionary: row),
        missing.contains(entry.id), result[entry.id] == nil
      else {
        complete = false
        continue
      }
      result[entry.id] = snapshot(entry, visibility: .hidden, primaryScreenTop: primaryScreenTop)
    }
    for id in missing where result[id] == nil {
      result[id] = .init(
        frame: .zero, title: nil, visibility: complete ? .closed : .unavailable,
        closureEvidence: complete ? .windowServer : nil)
    }
    return result
  }

  static func resolve(
    entries: [[String: Any]], windowIDs: Set<CGWindowID>, primaryScreenTop: Double
  ) -> [CGWindowID: WindowTargetSnapshot] {
    var result: [CGWindowID: WindowTargetSnapshot] = [:]
    var foreground: [WindowServerSource.ParsedWindowEntry] = []
    for row in entries.prefix(maximumInspectedWindows) {
      guard let entry = WindowServerSource.ParsedWindowEntry(dictionary: row) else { continue }
      if windowIDs.contains(entry.id) {
        let covers = foreground.filter { $0.layer >= entry.layer }.map(\.frame)
        let visible =
          entry.isVisible && WindowCoverage.hasVisibleArea(in: entry.frame, behind: covers)
        result[entry.id] = snapshot(
          entry, visibility: visible ? .visible : .hidden, primaryScreenTop: primaryScreenTop)
      }
      if entry.isVisible, !WindowTrackingExclusions.transparentOverlays.contains(entry.id),
        entry.layer >= WindowServerSource.normalWindowLayer,
        entry.layer < firstSystemOverlayLayer,
        entry.opacity >= opaqueWindowAlpha
      {
        foreground.append(entry)
      }
    }
    return result
  }

  private static func snapshot(
    _ entry: WindowServerSource.ParsedWindowEntry,
    visibility: WindowTargetSnapshot.Visibility, primaryScreenTop: Double
  ) -> WindowTargetSnapshot {
    .init(
      frame: ScreenCoordinates.appKitRect(
        fromAccessibility: entry.frame, primaryScreenTop: primaryScreenTop),
      title: entry.windowTitle, visibility: visibility, windowLayer: entry.layer,
      ownerPID: entry.ownerPID, isOnScreen: entry.isOnScreen)
  }

  private static func unavailable(_ windowIDs: Set<CGWindowID>) -> [CGWindowID:
    WindowTargetSnapshot]
  {
    Dictionary(
      uniqueKeysWithValues: windowIDs.map {
        ($0, WindowTargetSnapshot(frame: .zero, title: nil, visibility: .unavailable))
      })
  }
}
