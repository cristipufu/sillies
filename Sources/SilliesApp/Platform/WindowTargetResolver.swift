import AppKit
import CoreGraphics
import SilliesCore

struct WindowTargetSnapshot: Sendable {
  let frame: CGRect
  let title: String?
}

/// Single-window metadata reads. Private to this file so callers must go through `WindowTargetMetadata`'s
/// asynchronous worker queue and can never invoke WindowServer IPC on the main actor.
private enum WindowTargetResolver {
  private static let minimumVisibleAlpha: Double = 0.05

  static func candidate(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetCandidate? {
    dispatchPrecondition(condition: .notOnQueue(.main))
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
  ) -> WindowTargetSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let entry = windowEntry(for: windowID),
      (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
      (entry[kCGWindowAlpha as String] as? Double ?? 1) > minimumVisibleAlpha,
      let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
      let cgFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { return nil }
    let frame = ScreenCoordinates.appKitRect(
      fromAccessibility: cgFrame, primaryScreenTop: primaryScreenTop)
    let title = entry[kCGWindowName as String] as? String
    return WindowTargetSnapshot(frame: frame, title: title)
  }

  private static func windowEntry(for windowID: CGWindowID) -> [String: Any]? {
    dispatchPrecondition(condition: .notOnQueue(.main))
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
        dispatchPrecondition(condition: .notOnQueue(.main))
        continuation.resume(returning: read(windowID, primaryScreenTop))
      }
    }
  }

  func snapshots(
    for windowIDs: Set<CGWindowID>, primaryScreenTop: Double
  ) async -> [CGWindowID: WindowTargetSnapshot] {
    guard !Task.isCancelled, !windowIDs.isEmpty else { return [:] }
    return await withCheckedContinuation { continuation in
      queue.async {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var result: [CGWindowID: WindowTargetSnapshot] = [:]
        for windowID in windowIDs {
          if let snapshot = WindowTargetResolver.currentSnapshot(
            for: windowID, primaryScreenTop: primaryScreenTop)
          {
            result[windowID] = snapshot
          }
        }
        continuation.resume(returning: result)
      }
    }
  }

  func regions(primaryScreenTop: Double) async -> [DragWindowRegion] {
    guard !Task.isCancelled else { return [] }
    return await withCheckedContinuation { continuation in
      queue.async {
        dispatchPrecondition(condition: .notOnQueue(.main))
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
