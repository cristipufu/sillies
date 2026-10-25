import AppKit
import CoreGraphics
import SilliesCore

/// Resolves the application window underneath a dragged companion and queries single-window bounds
/// for bound companions without full window-list polling.
enum WindowTargetResolver {
  private static let minimumVisibleAlpha: Double = 0.05
  private static let maxStackSearchDepth = 16

  @MainActor
  static func resolveTarget(
    at screenPoint: CGPoint, excludingWindowNumbers: Set<Int>
  ) -> WindowTargetCandidate? {
    var below = 0
    var candidateNumber = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: below)
    var steps = 0
    let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
    let minimumSize = PointerWindowGesture.defaultMinimumWindowSize

    while candidateNumber > 0 && steps < maxStackSearchDepth {
      steps += 1
      if !excludingWindowNumbers.contains(candidateNumber) {
        let windowID = CGWindowID(candidateNumber)
        if let entry = windowEntry(for: windowID),
          (entry[kCGWindowLayer as String] as? Int) == 0,
          (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
          (entry[kCGWindowAlpha as String] as? Double ?? 1) > minimumVisibleAlpha,
          let pid = entry[kCGWindowOwnerPID as String] as? Int32,
          let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
          let cgFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        {
          let frame = ScreenCoordinates.appKitRect(
            fromAccessibility: cgFrame, primaryScreenTop: primaryTop)
          if frame.width >= minimumSize.width && frame.height >= minimumSize.height {
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let ownerName =
              runningApp?.localizedName
              ?? (entry[kCGWindowOwnerName as String] as? String)
              ?? "App"
            let title = entry[kCGWindowName as String] as? String
            return WindowTargetCandidate(
              windowID: windowID,
              processID: pid,
              appName: ownerName,
              bundleIdentifier: runningApp?.bundleIdentifier,
              windowTitle: title,
              frame: frame)
          }
        }
      }
      below = candidateNumber
      candidateNumber = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: below)
    }
    return nil
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
