import CoreGraphics
import Foundation
import SilliesCore

/// One bounded metadata stack serves every bound companion. No image capture or AX queries.
enum BoundWindowSnapshots {
  private static let maximumInspectedWindows = 256
  private static let opaqueWindowAlpha = 0.99

  static func read(windowIDs: Set<CGWindowID>, primaryScreenTop: Double) -> [CGWindowID:
    WindowTargetSnapshot]
  {
    guard let snapshot = WindowMetadataReader.snapshot(.optionAll, kCGNullWindowID) else {
      return Dictionary(
        uniqueKeysWithValues: windowIDs.map {
          ($0, WindowTargetSnapshot(frame: .zero, title: nil, visibility: .unavailable))
        })
    }
    return resolve(
      entries: snapshot.entries, windowIDs: windowIDs, primaryScreenTop: primaryScreenTop)
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
        result[entry.id] = WindowTargetSnapshot(
          frame: ScreenCoordinates.appKitRect(
            fromAccessibility: entry.frame, primaryScreenTop: primaryScreenTop),
          title: entry.windowTitle, visibility: visible ? .visible : .hidden,
          windowLayer: entry.layer)
      }
      if entry.isVisible, !WindowTrackingExclusions.transparentOverlays.contains(entry.id),
        entry.layer >= WindowServerSource.normalWindowLayer,
        entry.opacity >= opaqueWindowAlpha
      {
        foreground.append(entry)
      }
    }
    return result
  }
}
