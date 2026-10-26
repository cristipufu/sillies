import CoreGraphics
import Foundation
import SilliesCore

struct WindowServerObservation: Sendable {
  let processID: pid_t
  let windowID: CGWindowID?
  let frame: CGRect?
  let capturedAt: TimeInterval
  var windowLayer: Int = WindowServerSource.normalWindowLayer
  var backgroundWindowIDs: Set<Int>?
  var inputWindowFrames: [Int: CGRect]?
}

/// Public window metadata only. No images, window titles, or screen-capture permission.
/// Discovery is infrequent; manipulation reads are restricted to one known window.
final class WindowServerSource: @unchecked Sendable {
  struct Candidate: Sendable, Equatable {
    let id: UInt32
    let layer: Int
    let frame: CGRect
  }

  private struct Request {
    let processID: pid_t
    let windowID: CGWindowID?
    let discover: Bool
    let preferredFrame: CGRect?
    let preferredPoint: CGPoint?
    let roleSnapshot: AccessibilityWindowRoleSnapshot?
    let requiresVerifiedFloatingRole: Bool
    let isManipulatingWindow: Bool
  }

  static let normalWindowLayer = Int(CGWindowLevelForKey(.normalWindow))
  static let floatingWindowLayer = Int(CGWindowLevelForKey(.floatingWindow))
  private static let minimumTrackableWindowWidth: Double = 260
  private static let minimumTrackableWindowHeight: Double = 180
  static let minimumTrackableWindowSize = CGSize(
    width: minimumTrackableWindowWidth, height: minimumTrackableWindowHeight)
  private static let unassignedLayer = -1
  private static let defaultWindowAlpha: Double = 1.0
  private static let minimumVisibleAlpha: Double = 0.05
  private static let preferredFrameTolerance: Double = 6.0
  private static let interactiveBorderTolerance: Double = PointerWindowGesture.hitSlop

  static func isTrackableWindowLayer(_ layer: Int, ownerPID: pid_t) -> Bool {
    if layer == normalWindowLayer { return true }
    return layer == floatingWindowLayer && ownerPID != ProcessInfo.processInfo.processIdentifier
  }

  static func isTrackableWindowSize(_ size: CGSize) -> Bool {
    size.width >= minimumTrackableWindowSize.width
      && size.height >= minimumTrackableWindowSize.height
  }

  static func chooseCandidate(
    from candidates: [Candidate],
    preferredFrame: CGRect?,
    preferredPoint: CGPoint?,
    currentWindowID: CGWindowID?,
    roleSnapshot: AccessibilityWindowRoleSnapshot? = nil,
    requiresVerifiedFloatingRole: Bool = false,
    isManipulatingWindow: Bool = false
  ) -> Candidate? {
    let eligible = filterEligibleCandidates(
      from: candidates,
      roleSnapshot: roleSnapshot,
      currentWindowID: currentWindowID,
      requiresVerifiedFloatingRole: requiresVerifiedFloatingRole,
      isManipulatingWindow: isManipulatingWindow)
    guard !eligible.isEmpty else { return nil }

    if isManipulatingWindow,
      let currentWindowID,
      let activeManipulatedWindow = eligible.first(where: { $0.id == currentWindowID })
    {
      return activeManipulatedWindow
    }

    let hasFloatingCandidate = eligible.contains { $0.layer != normalWindowLayer }
    // When all eligible windows are standard normal-layer windows, WindowServer's front-to-back
    // ordering is already the exact focus order.
    guard hasFloatingCandidate else { return eligible.first }

    if let point = preferredPoint,
      let clicked = candidateContainingClickPoint(
        point, in: eligible, currentWindowID: currentWindowID)
    {
      return clicked
    }

    if let preferred = preferredFrame,
      let matched = eligible.first(where: { framesMatch($0.frame, preferred) })
    {
      return matched
    }
    if let currentWindowID,
      let existing = eligible.first(where: { $0.id == currentWindowID })
    {
      return existing
    }
    return eligible.first
  }

  static func isEligibleCandidate(
    _ candidate: Candidate,
    roleSnapshot: AccessibilityWindowRoleSnapshot?,
    currentWindowID: CGWindowID?,
    requiresVerifiedFloatingRole: Bool,
    isManipulatingWindow: Bool = false
  ) -> Bool {
    let isLockedCurrentWindow = isManipulatingWindow && candidate.id == currentWindowID
    guard isLockedCurrentWindow || isTrackableWindowSize(candidate.frame.size) else { return false }
    if let roleSnapshot,
      !isLockedCurrentWindow,
      matchesAnyFrame(candidate.frame, in: roleSnapshot.nonStandardWindowFrames)
    {
      return false
    }
    if candidate.layer == floatingWindowLayer {
      if isLockedCurrentWindow {
        return true
      }
      if let roleSnapshot {
        return matchesAnyFrame(candidate.frame, in: roleSnapshot.standardWindowFrames)
      }
      return !requiresVerifiedFloatingRole
    }
    return true
  }

  private static func filterEligibleCandidates(
    from candidates: [Candidate],
    roleSnapshot: AccessibilityWindowRoleSnapshot?,
    currentWindowID: CGWindowID?,
    requiresVerifiedFloatingRole: Bool,
    isManipulatingWindow: Bool = false
  ) -> [Candidate] {
    let filtered = candidates.filter {
      isEligibleCandidate(
        $0,
        roleSnapshot: roleSnapshot,
        currentWindowID: currentWindowID,
        requiresVerifiedFloatingRole: requiresVerifiedFloatingRole,
        isManipulatingWindow: isManipulatingWindow)
    }
    guard let roleSnapshot else {
      return filtered
    }
    if roleSnapshot.standardWindowFrames.isEmpty {
      return roleSnapshot.hasVerifiedWindowList || !roleSnapshot.nonStandardWindowFrames.isEmpty
        ? [] : filtered
    }
    let unmatchedStandardFrames = roleSnapshot.standardWindowFrames.filter { standardFrame in
      !filtered.contains { framesMatch($0.frame, standardFrame) }
    }
    let verified = filtered.filter {
      isVerifiedStandardCandidate(
        $0,
        roleSnapshot: roleSnapshot,
        unmatchedStandardFrames: unmatchedStandardFrames,
        currentWindowID: currentWindowID,
        isManipulatingWindow: isManipulatingWindow)
    }
    return verified.isEmpty ? filtered : verified
  }

  private static func isVerifiedStandardCandidate(
    _ candidate: Candidate,
    roleSnapshot: AccessibilityWindowRoleSnapshot,
    unmatchedStandardFrames: [CGRect],
    currentWindowID: CGWindowID?,
    isManipulatingWindow: Bool
  ) -> Bool {
    if isManipulatingWindow && candidate.id == currentWindowID {
      return true
    }
    if matchesAnyFrame(candidate.frame, in: roleSnapshot.standardWindowFrames) {
      return true
    }
    guard candidate.layer == normalWindowLayer, !unmatchedStandardFrames.isEmpty else {
      return false
    }
    return matchesStandardWindowSize(candidate.frame.size, in: unmatchedStandardFrames)
      || matchesResizeAnchor(candidate.frame, in: unmatchedStandardFrames)
  }

  private static func matchesStandardWindowSize(
    _ size: CGSize, in standardFrames: [CGRect]
  ) -> Bool {
    standardFrames.contains { standard in
      abs(size.width - standard.width) <= preferredFrameTolerance
        && abs(size.height - standard.height) <= preferredFrameTolerance
    }
  }

  private static func matchesResizeAnchor(_ frame: CGRect, in standardFrames: [CGRect]) -> Bool {
    standardFrames.contains { standard in
      let sharesHorizontalEdge =
        abs(frame.minX - standard.minX) <= preferredFrameTolerance
        || abs(frame.maxX - standard.maxX) <= preferredFrameTolerance
      let sharesVerticalEdge =
        abs(frame.minY - standard.minY) <= preferredFrameTolerance
        || abs(frame.maxY - standard.maxY) <= preferredFrameTolerance
      if sharesHorizontalEdge && sharesVerticalEdge {
        return true
      }
      return abs(frame.midX - standard.midX) <= preferredFrameTolerance
        && abs(frame.midY - standard.midY) <= preferredFrameTolerance
    }
  }

  private static func candidateContainingClickPoint(
    _ point: CGPoint,
    in candidates: [Candidate],
    currentWindowID: CGWindowID?
  ) -> Candidate? {
    for candidate in candidates {
      if candidate.id == currentWindowID,
        interactiveFrame(for: candidate.frame).contains(point)
      {
        return candidate
      }
      if interactiveFrame(for: candidate.frame).contains(point) {
        return candidate
      }
    }
    return nil
  }

  private static func interactiveFrame(for frame: CGRect) -> CGRect {
    frame.insetBy(dx: -interactiveBorderTolerance, dy: -interactiveBorderTolerance)
  }

  private static func matchesAnyFrame(_ frame: CGRect, in frames: [CGRect]) -> Bool {
    frames.contains { framesMatch(frame, $0) }
  }

  private let queue = DispatchQueue(label: "app.sillies.window-geometry", qos: .userInteractive)
  private let lock = NSLock()
  private var pending = false
  private var queued: Request?
  private let deliver: @Sendable (WindowServerObservation) -> Void

  init(deliver: @escaping @Sendable (WindowServerObservation) -> Void) { self.deliver = deliver }

  func refresh(
    processID: pid_t,
    windowID: CGWindowID?,
    discover: Bool,
    preferredFrame: CGRect? = nil,
    preferredPoint: CGPoint? = nil,
    roleSnapshot: AccessibilityWindowRoleSnapshot? = nil,
    requiresVerifiedFloatingRole: Bool = false,
    isManipulatingWindow: Bool = false
  ) {
    lock.lock()
    if pending {
      let sameProcess = queued?.processID == processID
      let mergedDiscover =
        isManipulatingWindow
        ? discover
        : ((sameProcess ? (queued?.discover ?? false) : false) || discover)
      let mergedFrame = preferredFrame ?? (sameProcess ? queued?.preferredFrame : nil)
      let mergedPoint = preferredPoint ?? (sameProcess ? queued?.preferredPoint : nil)
      let mergedSnapshot = roleSnapshot ?? (sameProcess ? queued?.roleSnapshot : nil)
      queued = Request(
        processID: processID,
        windowID: windowID,
        discover: mergedDiscover,
        preferredFrame: mergedFrame,
        preferredPoint: mergedPoint,
        roleSnapshot: mergedSnapshot,
        requiresVerifiedFloatingRole: requiresVerifiedFloatingRole,
        isManipulatingWindow: isManipulatingWindow)
      lock.unlock()
      return
    }
    pending = true
    lock.unlock()
    enqueue(
      Request(
        processID: processID,
        windowID: windowID,
        discover: discover,
        preferredFrame: preferredFrame,
        preferredPoint: preferredPoint,
        roleSnapshot: roleSnapshot,
        requiresVerifiedFloatingRole: requiresVerifiedFloatingRole,
        isManipulatingWindow: isManipulatingWindow))
  }

  private func enqueue(_ request: Request) {
    queue.async { [self] in
      performRefresh(request)
      lock.lock()
      if let next = queued {
        queued = nil
        lock.unlock()
        enqueue(next)
      } else {
        pending = false
        lock.unlock()
      }
    }
  }

  private func performRefresh(_ request: Request) {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let processID = request.processID
    let windowID = request.windowID
    let discover = request.discover
    let options: CGWindowListOption =
      discover || windowID == nil
      ? [.optionOnScreenOnly] : [.optionIncludingWindow]
    let reference = discover ? kCGNullWindowID : (windowID ?? kCGNullWindowID)
    let capturedAt = ProcessInfo.processInfo.systemUptime
    let entries = CGWindowListCopyWindowInfo(options, reference) as? [[String: Any]] ?? []
    let backgroundIDs: Set<Int>? =
      discover || windowID == nil
      ? Set(
        entries.compactMap { row in
          guard
            (row[kCGWindowLayer as String] as? Int ?? Self.normalWindowLayer)
              < Self.normalWindowLayer
          else { return nil }
          return row[kCGWindowNumber as String] as? Int
        }) : nil
    let inputFrames: [Int: CGRect]? =
      discover || windowID == nil
      ? Dictionary(
        uniqueKeysWithValues: entries.compactMap { row in
          guard
            (row[kCGWindowLayer as String] as? Int ?? Self.unassignedLayer)
              >= Self.normalWindowLayer,
            let id = row[kCGWindowNumber as String] as? Int,
            let bounds = row[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
          else { return nil }
          return (id, frame)
        }) : nil
    var candidates: [Candidate] = []
    for entry in entries {
      guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32,
        ownerPID == processID,
        let layer = entry[kCGWindowLayer as String] as? Int,
        Self.isTrackableWindowLayer(layer, ownerPID: ownerPID),
        (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
        (entry[kCGWindowAlpha as String] as? Double ?? Self.defaultWindowAlpha)
          > Self.minimumVisibleAlpha,
        let id = entry[kCGWindowNumber as String] as? UInt32,
        let bounds = entry[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        id == windowID || Self.isTrackableWindowSize(frame.size)
      else { continue }
      candidates.append(Candidate(id: id, layer: layer, frame: frame))
    }

    let chosen = Self.chooseCandidate(
      from: candidates,
      preferredFrame: request.preferredFrame,
      preferredPoint: request.preferredPoint,
      currentWindowID: windowID,
      roleSnapshot: request.roleSnapshot,
      requiresVerifiedFloatingRole: request.requiresVerifiedFloatingRole,
      isManipulatingWindow: request.isManipulatingWindow)

    if let chosen {
      deliver(
        WindowServerObservation(
          processID: processID, windowID: chosen.id, frame: chosen.frame, capturedAt: capturedAt,
          windowLayer: chosen.layer, backgroundWindowIDs: backgroundIDs,
          inputWindowFrames: inputFrames))
      return
    }
    if !discover && windowID != nil && !request.isManipulatingWindow {
      performRefresh(
        Request(
          processID: processID,
          windowID: nil,
          discover: true,
          preferredFrame: request.preferredFrame,
          preferredPoint: request.preferredPoint,
          roleSnapshot: request.roleSnapshot,
          requiresVerifiedFloatingRole: request.requiresVerifiedFloatingRole,
          isManipulatingWindow: false))
      return
    }
    deliver(
      WindowServerObservation(
        processID: processID, windowID: nil, frame: nil, capturedAt: capturedAt,
        backgroundWindowIDs: backgroundIDs, inputWindowFrames: inputFrames))
  }

  static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= preferredFrameTolerance
      && abs(lhs.minY - rhs.minY) <= preferredFrameTolerance
      && abs(lhs.width - rhs.width) <= preferredFrameTolerance
      && abs(lhs.height - rhs.height) <= preferredFrameTolerance
  }
}
