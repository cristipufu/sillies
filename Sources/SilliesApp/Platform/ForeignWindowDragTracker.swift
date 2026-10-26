import AppKit
import QuartzCore
import SilliesCore

/// Coordinates display-linked pointer prediction, metadata validation, and release reconciliation
/// for foreign-window move and resize gestures.
@MainActor
final class ForeignWindowDragTracker: NSObject {
  private static let pointerDragStartThreshold: Double = 2
  private static let confirmedValidationInterval: Double = 0.1
  private static let pendingValidationInterval: Double = 1.0 / 120
  private static let releaseHoldDuration: Double = 0.18
  private static let releaseReconcileInterval: Double = 0.025
  private static let releaseErrorTolerance: Double = 3
  private static let lowPowerFrameRateCap: Float = 60

  private(set) var isDragging = false
  private(set) var pointerUpdates = 0
  private(set) var rejectedGestures = 0
  private var session: WindowDragSession?
  private var displayLink: CADisplayLink?
  private var pointerDown: CGPoint?
  private var pointerDownFrame: CGRect?
  private var pointerDownTime: Double = 0
  private var pointerDownCentered = false
  private var pointerDownProportional = false
  private var releaseStartedAt: Double = 0
  private var releaseDeadline: Double = 0
  private var releaseTask: DispatchWorkItem?
  private var lastValidationRead: Double = 0
  private var isLowPower = false

  var onPresentFrame: ((CGRect) -> Void)?
  var onRequestGeometryRefresh: (() -> Void)?
  var onDragStarted: (() -> Void)?
  var onEnded: (() -> Void)?

  var hasActiveSession: Bool { session != nil }
  var isPointerConfirmed: Bool { session?.mode == .pointer }
  var isResizeCandidate: Bool {
    guard let kind = session?.gesture.kind else { return false }
    if case .resize = kind { return true }
    return false
  }

  func beginCandidate(
    frame: CGRect?, hasWindow: Bool, pointer: CGPoint, at time: Double,
    centered: Bool, proportional: Bool, isLowPower: Bool
  ) {
    cancel()
    self.isLowPower = isLowPower
    pointerDown = pointer
    pointerDownFrame = frame
    pointerDownTime = time
    pointerDownCentered = centered
    pointerDownProportional = proportional
    attachCandidateIfNeeded(frame: frame, hasWindow: hasWindow, isLowPower: isLowPower)
  }

  func attachCandidateIfNeeded(frame: CGRect?, hasWindow: Bool, isLowPower: Bool) {
    self.isLowPower = isLowPower
    guard session == nil, let frame, let pointerDown, hasWindow else { return }
    guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
      self.pointerDown = nil
      self.pointerDownFrame = nil
      return
    }
    if pointerDownFrame == nil { pointerDownFrame = frame }
    let currentPointer = NSEvent.mouseLocation
    let now = ProcessInfo.processInfo.systemUptime
    let gesture =
      PointerWindowGesture(
        frame: frame, pointer: pointerDown, at: pointerDownTime,
        centered: pointerDownCentered, proportional: pointerDownProportional)
      ?? PointerWindowGesture(
        frame: frame, pointer: currentPointer, at: now,
        centered: pointerDownCentered, proportional: pointerDownProportional)
      ?? verifiedWindowMoveGesture(frame: frame, currentPointer: currentPointer, now: now)
    session = gesture.map(WindowDragSession.init)
    if currentPointer != pointerDown {
      session?.record(pointer: currentPointer, at: now)
    }
    if session != nil { startDisplayLink() }
  }

  private func verifiedWindowMoveGesture(
    frame: CGRect, currentPointer: CGPoint, now: Double
  ) -> PointerWindowGesture? {
    guard let initialFrame = pointerDownFrame,
      let initialPointer = pointerDown,
      initialFrame.insetBy(dx: -PointerWindowGesture.hitSlop, dy: -PointerWindowGesture.hitSlop)
        .contains(initialPointer),
      abs(frame.width - initialFrame.width) < 0.5,
      abs(frame.height - initialFrame.height) < 0.5
    else { return nil }
    let moved = abs(frame.minX - initialFrame.minX) + abs(frame.minY - initialFrame.minY)
    guard moved > 1.0,
      hypot(currentPointer.x - initialPointer.x, currentPointer.y - initialPointer.y)
        > Self.pointerDragStartThreshold
    else { return nil }
    return PointerWindowGesture(
      kind: .move, frame: frame, pointer: currentPointer, at: now)
  }

  func updateDrag(
    frame: CGRect?, hasWindow: Bool, at time: Double, isLowPower: Bool
  ) -> Bool {
    attachCandidateIfNeeded(frame: frame, hasWindow: hasWindow, isLowPower: isLowPower)
    guard let active = session else { return false }
    if !isDragging {
      let point = NSEvent.mouseLocation
      let initial = active.gesture.initialPointer
      guard hypot(point.x - initial.x, point.y - initial.y) > Self.pointerDragStartThreshold else {
        return false
      }
      isDragging = true
      onDragStarted?()
    }
    presentPointerFrame()
    refreshValidationGeometry()
    startDisplayLink()
    return true
  }

  func validate(
    observationFrame: CGRect?, matchesTrackedWindow: Bool, currentFrame: CGRect?,
    capturedAt: Double, now: Double
  ) -> WindowDragSession.Decision? {
    guard let startedAt = session?.startedAt else { return nil }
    guard capturedAt >= startedAt else { return .ignore }
    guard matchesTrackedWindow, let next = observationFrame else {
      if isDragging && (isPointerConfirmed || observationFrame == nil) {
        return .ignore
      }
      invalidateSession()
      return nil
    }
    if isDragging {
      session?.record(pointer: NSEvent.mouseLocation, at: now)
      let previousMode = session?.mode
      guard let decision = session?.observe(next, capturedAt: capturedAt, now: now) else {
        return .ignore
      }
      if previousMode == .pointer && session?.mode == .metadata {
        rejectedGestures += 1
      }
      if decision == .usePointer {
        presentPointerFrame()
      }
      return decision
    }
    if releaseDeadline > 0 {
      let current = currentFrame ?? next
      let originError = abs(current.minX - next.minX) + abs(current.minY - next.minY)
      let sizeError = abs(current.width - next.width) + abs(current.height - next.height)
      if capturedAt < releaseStartedAt
        && originError + sizeError > Self.releaseErrorTolerance
        && now < releaseDeadline
      {
        return .ignore
      }
      cancel()
    }
    return .useMetadata
  }

  func end(canReconcile: Bool) {
    if isDragging { presentPointerFrame() }
    let wasDragging = isDragging
    isDragging = false
    displayLink?.invalidate()
    displayLink = nil
    if wasDragging && session?.mode == .pointer && canReconcile {
      let now = ProcessInfo.processInfo.systemUptime
      releaseStartedAt = now
      releaseDeadline = now + Self.releaseHoldDuration
      reconcileRelease()
    } else {
      cancel()
    }
    onRequestGeometryRefresh?()
    onEnded?()
  }

  func invalidateSession() {
    displayLink?.invalidate()
    displayLink = nil
    releaseTask?.cancel()
    releaseTask = nil
    isDragging = false
    session = nil
    releaseStartedAt = 0
    releaseDeadline = 0
    if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
      pointerDown = nil
      pointerDownFrame = nil
      pointerDownTime = 0
      pointerDownCentered = false
      pointerDownProportional = false
    }
  }

  func cancel() {
    invalidateSession()
    pointerDown = nil
    pointerDownFrame = nil
    pointerDownTime = 0
    pointerDownCentered = false
    pointerDownProportional = false
  }

  private func startDisplayLink() {
    guard displayLink == nil else { return }
    let targetScreen =
      session.flatMap { active in
        NSScreen.screens.first { $0.frame.intersects(active.gesture.initialFrame) }
      } ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen = targetScreen else { return }
    let link = screen.displayLink(target: self, selector: #selector(dragDisplayFrame(_:)))
    let maximum =
      isLowPower ? Self.lowPowerFrameRateCap : Float(screen.maximumFramesPerSecond)
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: min(Self.lowPowerFrameRateCap, maximum), maximum: maximum, preferred: maximum)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func dragDisplayFrame(_ link: CADisplayLink) {
    guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
      end(canReconcile: true)
      return
    }
    if !isDragging, let active = session {
      let point = NSEvent.mouseLocation
      let initial = active.gesture.initialPointer
      if hypot(point.x - initial.x, point.y - initial.y) > Self.pointerDragStartThreshold {
        isDragging = true
        onDragStarted?()
      }
    }
    guard isDragging else { return }
    presentPointerFrame()
    refreshValidationGeometry()
  }

  private func refreshValidationGeometry() {
    let now = ProcessInfo.processInfo.systemUptime
    let interval =
      session?.mode == .pointer ? Self.confirmedValidationInterval : Self.pendingValidationInterval
    if now - lastValidationRead >= interval {
      lastValidationRead = now
      onRequestGeometryRefresh?()
    }
  }

  private func presentPointerFrame() {
    guard isDragging else { return }
    let pointer = NSEvent.mouseLocation
    session?.record(pointer: pointer, at: ProcessInfo.processInfo.systemUptime)
    guard let frame = session?.predictedFrame(at: pointer) else { return }
    pointerUpdates += 1
    onPresentFrame?(frame)
  }

  private func reconcileRelease() {
    onRequestGeometryRefresh?()
    guard session != nil else { return }
    if ProcessInfo.processInfo.systemUptime >= releaseDeadline {
      cancel()
      onRequestGeometryRefresh?()
      return
    }
    let task = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.reconcileRelease() }
    }
    releaseTask = task
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.releaseReconcileInterval, execute: task)
  }
}
