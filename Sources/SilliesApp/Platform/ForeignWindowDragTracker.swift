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
  private var pointerDownTime: Double = 0
  private var pointerDownCentered = false
  private var pointerDownProportional = false
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

  func beginCandidate(
    frame: CGRect?, hasWindow: Bool, pointer: CGPoint, at time: Double,
    centered: Bool, proportional: Bool, isLowPower: Bool
  ) {
    cancel()
    self.isLowPower = isLowPower
    pointerDown = pointer
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
      return
    }
    session = PointerWindowGesture(
      frame: frame, pointer: pointerDown, at: pointerDownTime,
      centered: pointerDownCentered, proportional: pointerDownProportional
    ).map(WindowDragSession.init)
    if session != nil { startDisplayLink() }
  }

  func updateDrag(
    frame: CGRect?, hasWindow: Bool, at time: Double, isLowPower: Bool
  ) -> Bool {
    attachCandidateIfNeeded(frame: frame, hasWindow: hasWindow, isLowPower: isLowPower)
    guard session != nil else { return false }
    if !isDragging {
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
    guard let startedAt = session?.startedAt, matchesTrackedWindow, let next = observationFrame
    else {
      if session != nil { invalidateSession() }
      return nil
    }
    guard capturedAt >= startedAt else { return .ignore }
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
      if originError + sizeError > Self.releaseErrorTolerance && now < releaseDeadline {
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
      releaseDeadline = ProcessInfo.processInfo.systemUptime + Self.releaseHoldDuration
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
    releaseDeadline = 0
    if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
      pointerDown = nil
      pointerDownTime = 0
      pointerDownCentered = false
      pointerDownProportional = false
    }
  }

  func cancel() {
    invalidateSession()
    pointerDown = nil
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
