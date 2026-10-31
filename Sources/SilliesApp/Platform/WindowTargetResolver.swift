import AppKit
import CoreGraphics
import SilliesCore

struct WindowTargetSnapshot: Sendable {
  enum Visibility: Sendable { case visible, hidden, unavailable }
  let frame: CGRect
  let title: String?
  var visibility: Visibility = .visible
  var windowLayer: Int = 0

  func updating(_ target: WindowTargetCandidate) -> WindowTargetCandidate {
    guard visibility != .unavailable else { return target }
    var updated = target
    updated.isVisible = visibility == .visible
    guard updated.isVisible else { return updated }
    updated.frame = frame
    updated.windowLayer = windowLayer
    return updated
  }
}

/// Single-window metadata reads. Private to this file so callers must go through `WindowTargetMetadata`'s
/// asynchronous worker queue and can never invoke WindowServer IPC on the main actor.
private enum WindowTargetResolver {
  static let maxInspectedWindowEntries = 256
  private static let cache = WindowTargetCache()
  private static let roleSnapshotQueue = DispatchQueue(
    label: "app.sillies.drag-target-ax-warmup", qos: .utility)

  static func seedRoleSnapshot(_ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t) {
    cache.storeRole(snapshot, for: pid, at: ProcessInfo.processInfo.systemUptime)
  }

  static func updateCachedCandidateFrame(_ frame: CGRect, for windowID: CGWindowID) {
    cache.updateCandidateFrame(frame, for: windowID)
  }

  static func cacheCandidate(
    _ candidate: WindowTargetCandidate?, for windowID: CGWindowID, at now: TimeInterval
  ) {
    cache.storeCandidate(candidate, for: windowID, at: now)
  }

  static func nonBlockingRoleSnapshot(for pid: pid_t) -> AccessibilityWindowRoleSnapshot? {
    let request = cache.requestRole(for: pid, at: ProcessInfo.processInfo.systemUptime)
    if let generation = request.refresh {
      roleSnapshotQueue.async {
        let snapshot = AccessibilityWindowSource.roleSnapshot(for: pid)
        cache.finishRoleRefresh(
          snapshot, for: pid, generation: generation,
          at: ProcessInfo.processInfo.systemUptime)
      }
    }
    return request.snapshot
  }

  private static func cachedRoleSnapshot(for pid: pid_t) -> AccessibilityWindowRoleSnapshot? {
    let request = cache.requestRole(for: pid, at: ProcessInfo.processInfo.systemUptime)
    guard let generation = request.refresh else { return request.snapshot }
    let fetched = AccessibilityWindowSource.roleSnapshot(for: pid)
    cache.finishRoleRefresh(
      fetched, for: pid, generation: generation,
      at: ProcessInfo.processInfo.systemUptime)
    return cache.roleSnapshot(for: pid)
  }

  static func candidate(
    for windowID: CGWindowID, primaryScreenTop: Double
  ) -> WindowTargetCandidate? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard !WindowTrackingExclusions.shared.contains(windowID) else { return nil }
    let now = ProcessInfo.processInfo.systemUptime
    if case .cached(let candidate) = cache.candidate(for: windowID, at: now) {
      if let candidate,
        WindowTrackingExclusions.excludesSurface(windowID, ownerPID: candidate.processID)
      {
        return nil
      }
      return candidate
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
    guard !WindowTrackingExclusions.excludesSurface(windowID, ownerPID: pid) else {
      cacheCandidate(nil, for: windowID, at: now)
      return nil
    }
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
        continuation.resume(
          returning: BoundWindowSnapshots.read(
            windowIDs: windowIDs, primaryScreenTop: primaryScreenTop))
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
          if WindowTrackingExclusions.excludesSurface(parsed.id, ownerPID: parsed.ownerPID) {
            WindowTargetResolver.cacheCandidate(nil, for: parsed.id, at: now)
            return DragWindowRegion(
              windowID: parsed.id,
              frame: ScreenCoordinates.appKitRect(
                fromAccessibility: parsed.frame, primaryScreenTop: primaryScreenTop))
          }
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
