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
  static let defaultWindowAlpha: Double = 1.0
  static let minimumVisibleAlpha: Double = 0.05
  static let maxInspectedWindowEntries = 256
  private static let roleSnapshotCacheTTL: TimeInterval = 1.0
  private static let roleSnapshotCacheLock = NSLock()
  private nonisolated(unsafe) static var cachedRoleSnapshots:
    [pid_t: (snapshot: AccessibilityWindowRoleSnapshot?, capturedAt: TimeInterval)] = [:]

  private static func cachedRoleSnapshot(for pid: pid_t) -> AccessibilityWindowRoleSnapshot? {
    let now = ProcessInfo.processInfo.systemUptime
    roleSnapshotCacheLock.lock()
    if let entry = cachedRoleSnapshots[pid], now - entry.capturedAt < roleSnapshotCacheTTL {
      roleSnapshotCacheLock.unlock()
      return entry.snapshot
    }
    roleSnapshotCacheLock.unlock()
    let fetched = AccessibilityWindowSource.roleSnapshot(for: pid)
    roleSnapshotCacheLock.lock()
    if cachedRoleSnapshots.count >= 32 {
      cachedRoleSnapshots.removeAll(keepingCapacity: true)
    }
    cachedRoleSnapshots[pid] = (fetched, ProcessInfo.processInfo.systemUptime)
    roleSnapshotCacheLock.unlock()
    return fetched
  }

  static func candidate(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetCandidate? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let entry = windowEntry(for: windowID),
      let pid = entry[kCGWindowOwnerPID as String] as? Int32,
      let layer = entry[kCGWindowLayer as String] as? Int,
      WindowServerSource.isTrackableWindowLayer(layer, ownerPID: pid),
      (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
      (entry[kCGWindowAlpha as String] as? Double ?? defaultWindowAlpha) > minimumVisibleAlpha,
      let bounds = entry[kCGWindowBounds as String] as? [String: Any],
      let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
      WindowServerSource.isTrackableWindowSize(cgFrame.size)
    else { return nil }
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let app = NSRunningApplication(processIdentifier: pid)
    if let app, pid != currentPID {
      guard TrackableApplicationPolicy.isTrackable(app) else { return nil }
    }
    let snapshot = pid == currentPID ? nil : cachedRoleSnapshot(for: pid)
    let windowCandidate = WindowServerSource.Candidate(id: windowID, layer: layer, frame: cgFrame)
    guard
      WindowServerSource.isEligibleCandidate(
        windowCandidate,
        roleSnapshot: snapshot,
        currentWindowID: nil,
        requiresVerifiedFloatingRole: snapshot != nil)
    else { return nil }
    return WindowTargetCandidate(
      windowID: windowID, processID: pid,
      appName: app?.localizedName ?? (entry[kCGWindowOwnerName as String] as? String) ?? "App",
      bundleIdentifier: app?.bundleIdentifier,
      windowTitle: entry[kCGWindowName as String] as? String,
      frame: ScreenCoordinates.appKitRect(
        fromAccessibility: cgFrame, primaryScreenTop: primaryScreenTop),
      windowLayer: layer)
  }

  static func currentSnapshot(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let entry = windowEntry(for: windowID),
      (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
      (entry[kCGWindowAlpha as String] as? Double ?? defaultWindowAlpha) > minimumVisibleAlpha,
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
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var trackableProcesses: [pid_t: Bool] = [:]

        let regions = entries.prefix(WindowTargetResolver.maxInspectedWindowEntries).compactMap {
          entry -> DragWindowRegion? in
          guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
            let layer = entry[kCGWindowLayer as String] as? Int,
            WindowServerSource.isTrackableWindowLayer(layer, ownerPID: pid),
            (entry[kCGWindowAlpha as String] as? Double ?? WindowTargetResolver.defaultWindowAlpha)
              > WindowTargetResolver.minimumVisibleAlpha,
            let id = entry[kCGWindowNumber as String] as? UInt32,
            let bounds = entry[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
            WindowServerSource.isTrackableWindowSize(frame.size)
          else { return nil }

          let isProcessTrackable: Bool
          if let cached = trackableProcesses[pid] {
            isProcessTrackable = cached
          } else {
            let allowed: Bool
            if pid == currentPID {
              allowed = true
            } else if let app = NSRunningApplication(processIdentifier: pid) {
              allowed = TrackableApplicationPolicy.isTrackable(app)
            } else {
              allowed = true
            }
            trackableProcesses[pid] = allowed
            isProcessTrackable = allowed
          }
          guard isProcessTrackable else { return nil }

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
