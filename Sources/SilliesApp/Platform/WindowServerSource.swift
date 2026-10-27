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

  struct ParsedWindowEntry {
    let id: UInt32
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let isVisible: Bool
    let frame: CGRect
    let ownerName: String?
    let windowTitle: String?

    init?(dictionary: [String: Any]) {
      guard let id = dictionary[kCGWindowNumber as String] as? UInt32,
        let ownerPID = dictionary[kCGWindowOwnerPID as String] as? Int32,
        let layer = dictionary[kCGWindowLayer as String] as? Int,
        let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
      else { return nil }
      let isOnScreen = (dictionary[kCGWindowIsOnscreen as String] as? Bool) != false
      let alpha = dictionary[kCGWindowAlpha as String] as? Double ?? defaultWindowAlpha
      self.id = id
      self.ownerPID = ownerPID
      self.layer = layer
      self.isOnScreen = isOnScreen
      self.isVisible = isOnScreen && alpha > minimumVisibleAlpha
      self.frame = frame
      self.ownerName = dictionary[kCGWindowOwnerName as String] as? String
      self.windowTitle = dictionary[kCGWindowName as String] as? String
    }

    var isTrackableLayer: Bool {
      WindowServerSource.isTrackableWindowLayer(layer, ownerPID: ownerPID)
    }

    var isTrackableSize: Bool {
      WindowServerSource.isTrackableWindowSize(frame.size)
    }
  }

  struct Request {
    let processID: pid_t
    let windowID: CGWindowID?
    let discover: Bool
    var preferredFrame: CGRect? = nil
    var preferredPoint: CGPoint? = nil
    var roleSnapshot: AccessibilityWindowRoleSnapshot? = nil
    var requiresVerifiedFloatingRole: Bool = false
    var isManipulatingWindow: Bool = false
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
  private static let maxInteriorOverlayAreaRatio: Double = 0.65
  private static let maxUnverifiedOverlayMinorDimension: Double = 320.0

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
    guard hasFloatingCandidate else {
      return canonicalCandidate(
        eligible.first, roleSnapshot: roleSnapshot, isManipulatingWindow: isManipulatingWindow)
    }

    if let point = preferredPoint,
      let clicked = candidateContainingClickPoint(
        point, in: eligible, currentWindowID: currentWindowID)
    {
      return canonicalCandidate(
        clicked, roleSnapshot: roleSnapshot, isManipulatingWindow: isManipulatingWindow)
    }

    if let preferred = preferredFrame,
      let matched = eligible.first(where: { framesMatch($0.frame, preferred) })
    {
      return canonicalCandidate(
        matched, roleSnapshot: roleSnapshot, isManipulatingWindow: isManipulatingWindow)
    }
    if let currentWindowID,
      let existing = eligible.first(where: { $0.id == currentWindowID })
    {
      return canonicalCandidate(
        existing, roleSnapshot: roleSnapshot, isManipulatingWindow: isManipulatingWindow)
    }
    return canonicalCandidate(
      eligible.first, roleSnapshot: roleSnapshot, isManipulatingWindow: isManipulatingWindow)
  }

  private static func canonicalCandidate(
    _ candidate: Candidate?,
    roleSnapshot: AccessibilityWindowRoleSnapshot?,
    isManipulatingWindow: Bool
  ) -> Candidate? {
    guard let candidate else { return nil }
    guard !isManipulatingWindow,
      let roleSnapshot,
      roleSnapshot.hasExactStandardWindowFrames,
      let standardFrame = roleSnapshot.standardWindowFrames.first(where: {
        framesMatch(candidate.frame, $0)
      })
    else {
      return candidate
    }
    return Candidate(id: candidate.id, layer: candidate.layer, frame: standardFrame)
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
      matchesAnyFrame(candidate.frame, in: roleSnapshot.nonStandardWindowFrames),
      !matchesAnyFrame(candidate.frame, in: roleSnapshot.standardWindowFrames)
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
    let preliminaries = candidates.filter {
      isEligibleCandidate(
        $0,
        roleSnapshot: roleSnapshot,
        currentWindowID: currentWindowID,
        requiresVerifiedFloatingRole: requiresVerifiedFloatingRole,
        isManipulatingWindow: isManipulatingWindow)
    }
    let filtered = preliminaries.filter {
      !isInteriorOverlayCandidate(
        $0,
        in: preliminaries,
        roleSnapshot: roleSnapshot,
        currentWindowID: currentWindowID,
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
    if !verified.isEmpty {
      return verified
    }
    return roleSnapshot.hasVerifiedWindowList || !roleSnapshot.nonStandardWindowFrames.isEmpty
      ? [] : filtered
  }

  static func isInteriorOverlayCandidate(
    _ candidate: Candidate,
    in candidates: [Candidate],
    roleSnapshot: AccessibilityWindowRoleSnapshot?,
    currentWindowID: CGWindowID?,
    isManipulatingWindow: Bool = false
  ) -> Bool {
    guard !(isManipulatingWindow && candidate.id == currentWindowID),
      candidate.layer == normalWindowLayer
    else {
      return false
    }
    if let roleSnapshot {
      if matchesAnyFrame(candidate.frame, in: roleSnapshot.standardWindowFrames) {
        return false
      }
      if !roleSnapshot.hasExactStandardWindowFrames,
        matchesStandardWindowSize(candidate.frame.size, in: roleSnapshot.standardWindowFrames)
      {
        return false
      }
    } else if min(candidate.frame.width, candidate.frame.height)
      >= maxUnverifiedOverlayMinorDimension
    {
      return false
    }
    let candidateArea = candidate.frame.width * candidate.frame.height
    return candidates.contains { enclosing in
      guard enclosing.id != candidate.id,
        enclosing.layer == normalWindowLayer
      else {
        return false
      }
      let enclosingArea = enclosing.frame.width * enclosing.frame.height
      guard candidateArea < enclosingArea * maxInteriorOverlayAreaRatio else { return false }
      return enclosing.frame.insetBy(
        dx: -preferredFrameTolerance,
        dy: -preferredFrameTolerance
      ).contains(candidate.frame)
    }
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
    guard isManipulatingWindow || !roleSnapshot.hasExactStandardWindowFrames,
      candidate.layer == normalWindowLayer,
      !unmatchedStandardFrames.isEmpty
    else {
      return false
    }
    if matchesStandardWindowSize(candidate.frame.size, in: unmatchedStandardFrames) {
      return true
    }
    return matchesResizeAnchor(candidate.frame, in: unmatchedStandardFrames)
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

  func refresh(processID: pid_t, windowID: CGWindowID?, discover: Bool) {
    refresh(Request(processID: processID, windowID: windowID, discover: discover))
  }

  func refresh(_ request: Request) {
    lock.lock()
    if pending {
      queued = mergedRequest(from: request, existing: queued)
      lock.unlock()
      return
    }
    pending = true
    lock.unlock()
    enqueue(request)
  }

  private func mergedRequest(from incoming: Request, existing: Request?) -> Request {
    let sameProcess = existing?.processID == incoming.processID
    let mergedDiscover =
      incoming.isManipulatingWindow
      ? incoming.discover
      : ((sameProcess ? (existing?.discover ?? false) : false) || incoming.discover)
    return Request(
      processID: incoming.processID,
      windowID: incoming.windowID,
      discover: mergedDiscover,
      preferredFrame: incoming.preferredFrame ?? (sameProcess ? existing?.preferredFrame : nil),
      preferredPoint: incoming.preferredPoint ?? (sameProcess ? existing?.preferredPoint : nil),
      roleSnapshot: incoming.roleSnapshot ?? (sameProcess ? existing?.roleSnapshot : nil),
      requiresVerifiedFloatingRole: incoming.requiresVerifiedFloatingRole,
      isManipulatingWindow: incoming.isManipulatingWindow)
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
    let singleWindowRead = !discover && windowID != nil && request.isManipulatingWindow
    let options: CGWindowListOption =
      singleWindowRead ? [.optionIncludingWindow] : [.optionOnScreenOnly]
    let reference = singleWindowRead ? (windowID ?? kCGNullWindowID) : kCGNullWindowID
    let capturedAt = ProcessInfo.processInfo.systemUptime
    let entries = CGWindowListCopyWindowInfo(options, reference) as? [[String: Any]] ?? []
    let backgroundIDs = singleWindowRead ? nil : Self.extractBackgroundWindowIDs(from: entries)
    let inputFrames = singleWindowRead ? nil : Self.extractInputWindowFrames(from: entries)
    let candidates = Self.extractCandidates(
      from: entries, for: processID, currentWindowID: windowID)

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

  private static func extractBackgroundWindowIDs(from entries: [[String: Any]]) -> Set<Int> {
    Set(
      entries.compactMap { row in
        guard (row[kCGWindowLayer as String] as? Int ?? normalWindowLayer) < normalWindowLayer
        else { return nil }
        return row[kCGWindowNumber as String] as? Int
      })
  }

  private static func extractInputWindowFrames(from entries: [[String: Any]]) -> [Int: CGRect] {
    Dictionary(
      uniqueKeysWithValues: entries.compactMap { row in
        guard (row[kCGWindowLayer as String] as? Int ?? unassignedLayer) >= normalWindowLayer,
          let id = row[kCGWindowNumber as String] as? Int,
          let bounds = row[kCGWindowBounds as String] as? [String: Any],
          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return (id, frame)
      })
  }

  private static func extractCandidates(
    from entries: [[String: Any]],
    for processID: pid_t,
    currentWindowID: CGWindowID?
  ) -> [Candidate] {
    entries.compactMap { raw in
      guard let parsed = ParsedWindowEntry(dictionary: raw),
        parsed.ownerPID == processID,
        parsed.isTrackableLayer,
        parsed.isVisible,
        parsed.id == currentWindowID || parsed.isTrackableSize
      else { return nil }
      return Candidate(id: parsed.id, layer: parsed.layer, frame: parsed.frame)
    }
  }

  static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= preferredFrameTolerance
      && abs(lhs.minY - rhs.minY) <= preferredFrameTolerance
      && abs(lhs.width - rhs.width) <= preferredFrameTolerance
      && abs(lhs.height - rhs.height) <= preferredFrameTolerance
  }
}
