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
  static let maxInspectedWindowEntries = 256
  private static let maxCachedRoleSnapshots = 32
  private static let maxCachedWindowCandidates = 128
  private static let roleSnapshotCacheTTL: TimeInterval = 15.0
  private static let candidateCacheTTL: TimeInterval = 2.0
  private static let roleSnapshotCacheLock = NSLock()
  private static let candidateCacheLock = NSLock()
  private static let roleSnapshotQueue = DispatchQueue(
    label: "app.sillies.drag-target-ax-warmup", qos: .utility)
  private nonisolated(unsafe) static var cachedRoleSnapshots:
    [pid_t: (snapshot: AccessibilityWindowRoleSnapshot?, capturedAt: TimeInterval)] = [:]
  private nonisolated(unsafe) static var pendingRoleSnapshotPIDs: Set<pid_t> = []
  private nonisolated(unsafe) static var cachedWindowCandidates:
    [CGWindowID: (candidate: WindowTargetCandidate?, capturedAt: TimeInterval)] = [:]

  static func seedRoleSnapshot(_ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t) {
    guard pid > 0 else { return }
    let now = ProcessInfo.processInfo.systemUptime
    roleSnapshotCacheLock.lock()
    if cachedRoleSnapshots.count >= maxCachedRoleSnapshots {
      cachedRoleSnapshots.removeAll(keepingCapacity: true)
    }
    cachedRoleSnapshots[pid] = (snapshot, now)
    roleSnapshotCacheLock.unlock()
  }

  static func updateCachedCandidateFrame(_ frame: CGRect, for windowID: CGWindowID) {
    candidateCacheLock.lock()
    if let existing = cachedWindowCandidates[windowID], var candidate = existing.candidate {
      candidate.frame = frame
      cachedWindowCandidates[windowID] = (candidate, existing.capturedAt)
    }
    candidateCacheLock.unlock()
  }

  static func cacheCandidate(
    _ candidate: WindowTargetCandidate?, for windowID: CGWindowID, at now: TimeInterval
  ) {
    candidateCacheLock.lock()
    if cachedWindowCandidates.count >= maxCachedWindowCandidates {
      cachedWindowCandidates.removeAll(keepingCapacity: true)
    }
    cachedWindowCandidates[windowID] = (candidate, now)
    candidateCacheLock.unlock()
  }

  private static func lookupCachedCandidate(
    for windowID: CGWindowID, at now: TimeInterval
  ) -> (hit: Bool, candidate: WindowTargetCandidate?) {
    candidateCacheLock.lock()
    defer { candidateCacheLock.unlock() }
    guard let entry = cachedWindowCandidates[windowID],
      now - entry.capturedAt < candidateCacheTTL
    else {
      return (false, nil)
    }
    return (true, entry.candidate)
  }

  static func nonBlockingRoleSnapshot(for pid: pid_t) -> AccessibilityWindowRoleSnapshot? {
    let now = ProcessInfo.processInfo.systemUptime
    roleSnapshotCacheLock.lock()
    if let entry = cachedRoleSnapshots[pid] {
      let isFresh = now - entry.capturedAt < roleSnapshotCacheTTL
      let snapshot = entry.snapshot
      if isFresh {
        roleSnapshotCacheLock.unlock()
        return snapshot
      }
      scheduleRoleSnapshotWarmupLocked(for: pid)
      roleSnapshotCacheLock.unlock()
      return snapshot
    }
    scheduleRoleSnapshotWarmupLocked(for: pid)
    roleSnapshotCacheLock.unlock()
    return nil
  }

  private static func scheduleRoleSnapshotWarmupLocked(for pid: pid_t) {
    guard pid > 0, !pendingRoleSnapshotPIDs.contains(pid) else { return }
    pendingRoleSnapshotPIDs.insert(pid)
    roleSnapshotQueue.async {
      let fetched = AccessibilityWindowSource.roleSnapshot(for: pid)
      let capturedAt = ProcessInfo.processInfo.systemUptime
      roleSnapshotCacheLock.lock()
      pendingRoleSnapshotPIDs.remove(pid)
      if cachedRoleSnapshots.count >= maxCachedRoleSnapshots {
        cachedRoleSnapshots.removeAll(keepingCapacity: true)
      }
      cachedRoleSnapshots[pid] = (fetched, capturedAt)
      roleSnapshotCacheLock.unlock()
    }
  }

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
    if cachedRoleSnapshots.count >= maxCachedRoleSnapshots {
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
    let now = ProcessInfo.processInfo.systemUptime
    let cached = lookupCachedCandidate(for: windowID, at: now)
    if cached.hit {
      return cached.candidate
    }
    guard let parsed = parsedWindowEntry(for: windowID),
      parsed.isTrackableLayer,
      parsed.isVisible,
      parsed.isTrackableSize
    else {
      cacheCandidate(nil, for: windowID, at: now)
      return nil
    }
    let pid = parsed.ownerPID
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let app = NSRunningApplication(processIdentifier: pid)
    if let app, pid != currentPID {
      guard TrackableApplicationPolicy.isTrackable(app) else {
        cacheCandidate(nil, for: windowID, at: now)
        return nil
      }
    }
    let snapshot: AccessibilityWindowRoleSnapshot?
    if pid == currentPID {
      snapshot = nil
    } else if parsed.layer == WindowServerSource.normalWindowLayer {
      snapshot = nonBlockingRoleSnapshot(for: pid)
    } else {
      snapshot = cachedRoleSnapshot(for: pid)
    }
    let windowCandidate = WindowServerSource.Candidate(
      id: windowID, layer: parsed.layer, frame: parsed.frame)
    guard
      WindowServerSource.isEligibleCandidate(
        windowCandidate,
        roleSnapshot: snapshot,
        currentWindowID: nil,
        requiresVerifiedFloatingRole: snapshot != nil)
    else {
      cacheCandidate(nil, for: windowID, at: now)
      return nil
    }
    let resolved = WindowTargetCandidate(
      windowID: windowID, processID: pid,
      appName: app?.localizedName ?? parsed.ownerName ?? "App",
      bundleIdentifier: app?.bundleIdentifier,
      windowTitle: parsed.windowTitle,
      frame: ScreenCoordinates.appKitRect(
        fromAccessibility: parsed.frame, primaryScreenTop: primaryScreenTop),
      windowLayer: parsed.layer)
    cacheCandidate(resolved, for: windowID, at: now)
    return resolved
  }

  static func currentSnapshot(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let parsed = parsedWindowEntry(for: windowID),
      parsed.isVisible
    else { return nil }
    let frame = ScreenCoordinates.appKitRect(
      fromAccessibility: parsed.frame, primaryScreenTop: primaryScreenTop)
    return WindowTargetSnapshot(frame: frame, title: parsed.windowTitle)
  }

  private static func parsedWindowEntry(
    for windowID: CGWindowID
  ) -> WindowServerSource.ParsedWindowEntry? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let list =
      WindowMetadataReader.copyInfo([.optionIncludingWindow], windowID)
    guard let raw = list.first else { return nil }
    return WindowServerSource.ParsedWindowEntry(dictionary: raw)
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

  func seedRoleSnapshot(_ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t) {
    WindowTargetResolver.seedRoleSnapshot(snapshot, for: pid)
  }

  func updateCachedCandidateFrame(_ frame: CGRect, for windowID: CGWindowID) {
    WindowTargetResolver.updateCachedCandidateFrame(frame, for: windowID)
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
          WindowMetadataReader.copyInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        var processInfoByPID:
          [pid_t: (isTrackable: Bool, appName: String?, bundleIdentifier: String?)] = [:]
        var preliminaryEntries: [WindowServerSource.ParsedWindowEntry] = []
        var candidatesByPID: [pid_t: [WindowServerSource.Candidate]] = [:]

        for entry in entries.prefix(WindowTargetResolver.maxInspectedWindowEntries) {
          guard let parsed = WindowServerSource.ParsedWindowEntry(dictionary: entry),
            parsed.isTrackableLayer,
            parsed.isVisible,
            parsed.isTrackableSize
          else { continue }
          let pid = parsed.ownerPID
          let info: (isTrackable: Bool, appName: String?, bundleIdentifier: String?)
          if let cached = processInfoByPID[pid] {
            info = cached
          } else {
            let app = NSRunningApplication(processIdentifier: pid)
            let allowed: Bool
            if pid == currentPID {
              allowed = true
            } else if let app {
              allowed = TrackableApplicationPolicy.isTrackable(app)
            } else {
              allowed = true
            }
            let resolved = (
              isTrackable: allowed,
              appName: app?.localizedName,
              bundleIdentifier: app?.bundleIdentifier
            )
            processInfoByPID[pid] = resolved
            info = resolved
          }
          guard info.isTrackable else {
            WindowTargetResolver.cacheCandidate(nil, for: parsed.id, at: now)
            continue
          }
          preliminaryEntries.append(parsed)
          candidatesByPID[pid, default: []].append(
            WindowServerSource.Candidate(id: parsed.id, layer: parsed.layer, frame: parsed.frame))
        }

        let regions = preliminaryEntries.compactMap { parsed -> DragWindowRegion? in
          let pid = parsed.ownerPID
          let snapshot =
            pid == currentPID ? nil : WindowTargetResolver.nonBlockingRoleSnapshot(for: pid)
          let candidate = WindowServerSource.Candidate(
            id: parsed.id, layer: parsed.layer, frame: parsed.frame)
          let siblings = candidatesByPID[pid] ?? []
          let isEligible =
            WindowServerSource.isEligibleCandidate(
              candidate,
              roleSnapshot: snapshot,
              currentWindowID: nil,
              requiresVerifiedFloatingRole: snapshot != nil)
            && !WindowServerSource.isInteriorOverlayCandidate(
              candidate,
              in: siblings,
              roleSnapshot: snapshot,
              currentWindowID: nil)
          guard isEligible else {
            WindowTargetResolver.cacheCandidate(nil, for: parsed.id, at: now)
            return nil
          }
          let appKitFrame = ScreenCoordinates.appKitRect(
            fromAccessibility: parsed.frame, primaryScreenTop: primaryScreenTop)
          let info = processInfoByPID[pid]
          let targetCandidate = WindowTargetCandidate(
            windowID: parsed.id,
            processID: pid,
            appName: info?.appName ?? parsed.ownerName ?? "App",
            bundleIdentifier: info?.bundleIdentifier,
            windowTitle: parsed.windowTitle,
            frame: appKitFrame,
            windowLayer: parsed.layer)
          WindowTargetResolver.cacheCandidate(targetCandidate, for: parsed.id, at: now)
          return DragWindowRegion(windowID: parsed.id, frame: appKitFrame)
        }
        continuation.resume(returning: regions)
      }
    }
  }
}
