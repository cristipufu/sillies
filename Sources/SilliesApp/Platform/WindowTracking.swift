import AppKit
import ApplicationServices
import Observation
import QuartzCore
import SilliesCore

@MainActor
protocol WorkspaceEventProducer: AnyObject {
  var onEvent: ((WorkspaceEvent) -> Void)? { get set }
  func start()
  func stop()
  func configure(enabled: Bool, tracksWindows: Bool)
}

struct WindowGeometryChange {
  private static let minimumFrameElapsed: Double = 0.016

  let previous: CGRect
  let current: CGRect
  let elapsed: Double
  let resized: Bool
  var horizontalSpeed: Double {
    (current.midX - previous.midX) / max(elapsed, Self.minimumFrameElapsed)
  }
  var verticalSpeed: Double {
    (current.maxY - previous.maxY) / max(elapsed, Self.minimumFrameElapsed)
  }
  var widthSpeed: Double {
    (current.width - previous.width) / max(elapsed, Self.minimumFrameElapsed)
  }
}

@MainActor @Observable
final class WorkspaceTracker: NSObject, WorkspaceEventProducer {
  private static let accessibilityHeartbeatInterval: Double = 1.0
  private static let pollingHeartbeatInterval: Double = 0.25
  private static let discoveryTickMultiple = 2
  private static let followUpDiscoveryDelays: [Double] = [0.035, 0.11]
  private static let housekeepingInterval: Double = 5.0
  private static let userIdleThresholdSeconds: Double = 90
  private static let settleDelaySeconds: Double = 0.22
  private static let settleThrottleInterval: Double = 0.15
  private static let appChangeThrottleInterval: Double = 0.2
  private static let contextChangeThrottleInterval: Double = 1.0
  private static let userReturnThrottleInterval: Double = 2.0
  private static let scrollThrottleInterval: Double = 5.0
  private static let minimumScrollDelta: Double = 2.0
  private static let scrollIntensityScale: Double = 40.0
  private static let resizeDetectionEpsilon: Double = 0.5

  private(set) var hasAccessibility = AXIsProcessTrusted()
  private(set) var applicationName = "Your desktop"
  private(set) var bundleIdentifier: String?
  @ObservationIgnored private(set) var windowFrame: CGRect?
  private(set) var windowID: CGWindowID?
  private(set) var processID: pid_t = 0
  private(set) var isIdle = false
  private(set) var isSuspended = false
  private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  private(set) var receivedEvents = 0
  @ObservationIgnored private(set) var geometryReads = 0
  @ObservationIgnored var pointerUpdates: Int { dragTracker.pointerUpdates }
  @ObservationIgnored var rejectedPointerGestures: Int { dragTracker.rejectedGestures }
  @ObservationIgnored private(set) var backgroundWindowIDs: Set<Int> = []
  @ObservationIgnored private(set) var inputWindowFrames: [Int: CGRect] = [:]
  @ObservationIgnored private(set) var eventCounts: [EventKind: Int] = [:]
  @ObservationIgnored private(set) var latestGeometry: WindowGeometryChange?
  @ObservationIgnored var onEvent: ((WorkspaceEvent) -> Void)?
  @ObservationIgnored var onGeometryChanged: (() -> Void)?
  @ObservationIgnored var onEnvironmentChanged: (() -> Void)?
  @ObservationIgnored var onApplicationChanged: (() -> Void)?
  @ObservationIgnored private var accessibilitySource: AccessibilityWindowSource?
  @ObservationIgnored private var geometrySource: WindowServerSource?
  @ObservationIgnored private let dragTracker = ForeignWindowDragTracker()
  @ObservationIgnored private var globalMonitor: Any?
  @ObservationIgnored private var localMonitor: Any?
  @ObservationIgnored private var heartbeat: Timer?
  @ObservationIgnored private var idleTimer: Timer?
  @ObservationIgnored private var settleTimer: Timer?
  @ObservationIgnored private var discoveryTasks: [DispatchWorkItem] = []
  @ObservationIgnored private var throttle = EventThrottle()
  @ObservationIgnored private var isEnabled = true
  @ObservationIgnored private var tracksWindows = true
  @ObservationIgnored private var started = false
  @ObservationIgnored private var heartbeatTicks = 0
  @ObservationIgnored private var lastGeometryTime: Double = 0
  @ObservationIgnored private var currentManipulation: EventKind?
  @ObservationIgnored private let usesAccessibility: Bool

  init(useAccessibility: Bool = true) {
    usesAccessibility = useAccessibility
    super.init()
    hasAccessibility = useAccessibility && AXIsProcessTrusted()
    dragTracker.onPresentFrame = { [weak self] frame in
      guard let self else { return }
      self.publishGeometry(frame, windowID: self.windowID)
    }
    dragTracker.onRequestGeometryRefresh = { [weak self] in
      self?.refreshGeometry()
    }
    dragTracker.onDragStarted = { [weak self] in
      self?.settleTimer?.invalidate()
      self?.settleTimer = nil
    }
    dragTracker.onEnded = { [weak self] in
      self?.settleTimer?.invalidate()
      self?.settleTimer = nil
      self?.settle()
    }
  }

  func start() {
    guard !started else { return }
    started = true
    geometrySource = WindowServerSource { [weak self] value in
      DispatchQueue.main.async { [weak self] in self?.accept(value) }
    }
    accessibilitySource = AccessibilityWindowSource { [weak self] value in
      DispatchQueue.main.async { [weak self] in self?.acceptAccessibility(value) }
    }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(activated), name: NSWorkspace.didActivateApplicationNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil)
    for name in [
      NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] {
      center.addObserver(self, selector: #selector(suspend), name: name, object: nil)
    }
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      center.addObserver(self, selector: #selector(resume), name: name, object: nil)
    }
    center.addObserver(
      self, selector: #selector(environmentChanged),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(displaysChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(environmentChanged), name: .NSProcessInfoPowerStateDidChange,
      object: nil)
    for name in [
      NSWindow.didMoveNotification, NSWindow.didResizeNotification,
      NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(localWindowChanged(_:)), name: name, object: nil)
    }
    followFrontmostApplication(force: true)
    configureTimers()
  }

  func stop() {
    started = false
    accessibilitySource?.stop()
    accessibilitySource = nil
    geometrySource = nil
    removeInputMonitors()
    cancelFollowUpDiscovery()
    dragTracker.cancel()
    heartbeat?.invalidate()
    heartbeat = nil
    idleTimer?.invalidate()
    idleTimer = nil
    settleTimer?.invalidate()
    settleTimer = nil
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  func configure(enabled: Bool, tracksWindows: Bool) {
    guard enabled != isEnabled || tracksWindows != self.tracksWindows else { return }
    isEnabled = enabled
    self.tracksWindows = tracksWindows
    endDrag()
    if enabled && tracksWindows {
      followFrontmostApplication(force: true)
    } else {
      accessibilitySource?.stop()
    }
    configureTimers()
  }

  func requestAccessibility() {
    hasAccessibility = AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    if hasAccessibility { followFrontmostApplication(force: true) }
    configureTimers()
  }

  func refreshFocus() { followFrontmostApplication(force: true) }

  func refreshInputBackgrounds() {
    guard started, isEnabled, !isSuspended, !tracksWindows, backgroundWindowIDs.isEmpty else {
      return
    }
    geometrySource?.refresh(processID: processID, windowID: nil, discover: true)
  }

  func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  private func configureTimers() {
    heartbeat?.invalidate()
    heartbeat = nil
    idleTimer?.invalidate()
    idleTimer = nil
    guard started, isEnabled, !isSuspended else {
      cancelFollowUpDiscovery()
      removeInputMonitors()
      return
    }
    installInputMonitorsIfNeeded()
    if tracksWindows {
      let interval =
        hasAccessibility ? Self.accessibilityHeartbeatInterval : Self.pollingHeartbeatInterval
      let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, !self.dragTracker.isDragging else { return }
          self.followFrontmostApplication()
          self.heartbeatTicks += 1
          self.refreshGeometry(
            discover: self.windowID == nil
              || self.heartbeatTicks.isMultiple(of: Self.discoveryTickMultiple))
        }
      }
      timer.tolerance = hasAccessibility ? 0.15 : 0.03
      RunLoop.main.add(timer, forMode: .common)
      heartbeat = timer
    }
    idleTimer = Timer.scheduledTimer(
      withTimeInterval: Self.housekeepingInterval, repeats: true
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.housekeeping() }
    }
    idleTimer?.tolerance = 1
  }

  private func installInputMonitorsIfNeeded() {
    if globalMonitor == nil {
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel,
      ]) { [weak self] event in
        MainActor.assumeIsolated { self?.input(event) }
      }
    }
    if localMonitor == nil {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) {
        [weak self] event in
        self?.endDrag()
        return event
      }
    }
  }

  private func removeInputMonitors() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    globalMonitor = nil
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    localMonitor = nil
  }

  private func followFrontmostApplication(force: Bool = false) {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      guard
        NSApp.windows.contains(where: {
          $0.isVisible && $0.canBecomeMain && $0.styleMask.contains(.titled)
        })
      else { return }
    }
    guard force || processID != app.processIdentifier else { return }
    dragTracker.invalidateSession()
    processID = app.processIdentifier
    applicationName = app.localizedName ?? "Your app"
    bundleIdentifier = app.bundleIdentifier
    windowID = nil
    latestGeometry = nil
    if isEnabled && tracksWindows {
      if hasAccessibility { accessibilitySource?.observe(processID: processID) }
      refreshGeometry(discover: true)
      scheduleFollowUpDiscovery()
    }
    onApplicationChanged?()
  }

  private func cancelFollowUpDiscovery() {
    for task in discoveryTasks { task.cancel() }
    discoveryTasks.removeAll()
  }

  private func scheduleFollowUpDiscovery() {
    cancelFollowUpDiscovery()
    guard started, isEnabled, tracksWindows, !isSuspended else { return }
    for delay in Self.followUpDiscoveryDelays {
      let task = DispatchWorkItem { [weak self] in
        MainActor.assumeIsolated {
          guard let self, !self.dragTracker.isPointerConfirmed else { return }
          self.followFrontmostApplication()
          self.refreshGeometry(discover: true)
        }
      }
      discoveryTasks.append(task)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
  }

  private func refreshGeometry(discover: Bool = false) {
    guard started, isEnabled, tracksWindows, !isSuspended, processID != 0 else { return }
    geometrySource?.refresh(processID: processID, windowID: windowID, discover: discover)
  }

  private func accept(_ observation: WindowServerObservation) {
    guard observation.processID == processID, isEnabled, !isSuspended else { return }
    if let ids = observation.backgroundWindowIDs { backgroundWindowIDs = ids }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    if let frames = observation.inputWindowFrames {
      inputWindowFrames = frames.mapValues {
        ScreenCoordinates.appKitRect(fromAccessibility: $0, primaryScreenTop: top)
      }
    }
    guard tracksWindows else { return }
    geometryReads += 1
    var next = observation.frame.map {
      ScreenCoordinates.appKitRect(fromAccessibility: $0, primaryScreenTop: top)
    }
    if let id = observation.windowID, let next { inputWindowFrames[Int(id)] = next }
    // Native windows already provide synchronous bounds. Never overwrite them with stale IPC readback.
    if processID == ProcessInfo.processInfo.processIdentifier, let id = observation.windowID,
      let native = NSApp.window(withWindowNumber: Int(id)), native.isVisible
    {
      next = native.frame
    }
    if dragTracker.hasActiveSession {
      let decision = dragTracker.validate(
        observationFrame: next,
        matchesTrackedWindow: observation.windowID == windowID,
        currentFrame: windowFrame,
        capturedAt: observation.capturedAt,
        now: ProcessInfo.processInfo.systemUptime)
      if decision == .ignore || decision == .usePointer {
        return
      }
    }
    publishGeometry(next, windowID: observation.windowID)
    dragTracker.attachCandidateIfNeeded(
      frame: windowFrame, hasWindow: windowID != nil, isLowPower: isLowPower)
  }

  private func publishGeometry(_ next: CGRect?, windowID nextID: CGWindowID?) {
    let old = windowFrame
    let previousID = windowID
    guard old != next || previousID != nextID else { return }
    let time = ProcessInfo.processInfo.systemUptime
    windowFrame = next
    if windowID != nextID { windowID = nextID }
    latestGeometry = nil
    if let old, let next, previousID == nextID {
      let resized =
        abs(old.width - next.width) > Self.resizeDetectionEpsilon
        || abs(old.height - next.height) > Self.resizeDetectionEpsilon
      let change = WindowGeometryChange(
        previous: old, current: next, elapsed: time - lastGeometryTime, resized: resized)
      latestGeometry = change
      let kind: EventKind = resized ? .windowResized : .windowMoved
      if currentManipulation != kind {
        currentManipulation = kind
        let speed = hypot(change.horizontalSpeed, change.verticalSpeed)
        emit(kind, intensity: min(max(speed / 1200, 0.25), 1))
      }
      if !dragTracker.isDragging {
        settleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.settleDelaySeconds, repeats: false) { [weak self] _ in
          MainActor.assumeIsolated { self?.settle() }
        }
        settleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
      }
    }
    lastGeometryTime = time
    onGeometryChanged?()
    if old != nil && next == nil {
      emit(.windowDisappeared)
    } else if previousID != nextID {
      emit(.appChanged, interval: Self.appChangeThrottleInterval)
    }
  }

  private func acceptAccessibility(_ observation: WindowObservation) {
    guard observation.processID == processID, isEnabled, tracksWindows else { return }
    let discover =
      observation.reason == "activation"
      || observation.reason == kAXFocusedWindowChangedNotification
      || observation.reason == kAXMainWindowChangedNotification
    refreshGeometry(discover: discover)
    if observation.reason == kAXTitleChangedNotification
      || observation.reason == kAXSelectedChildrenChangedNotification
    {
      emit(.contextChanged, interval: Self.contextChangeThrottleInterval)
    }
  }

  private func input(_ event: NSEvent) {
    guard isEnabled, !isSuspended else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if isIdle {
      isIdle = false
      emit(.userReturned, interval: Self.userReturnThrottleInterval)
    }
    switch event.type {
    case .leftMouseDown:
      guard tracksWindows else { return }
      followFrontmostApplication()
      refreshGeometry(discover: true)
      scheduleFollowUpDiscovery()
      let eventPoint = event.cgEvent?.location
      let point =
        eventPoint.map { CGPoint(x: $0.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.y) }
        ?? NSEvent.mouseLocation
      dragTracker.beginCandidate(
        frame: windowFrame, hasWindow: windowID != nil, pointer: point, at: now,
        centered: event.modifierFlags.contains(.option),
        proportional: event.modifierFlags.contains(.shift),
        isLowPower: isLowPower)
    case .leftMouseDragged:
      guard tracksWindows else { return }
      let handled = dragTracker.updateDrag(
        frame: windowFrame, hasWindow: windowID != nil, at: now, isLowPower: isLowPower)
      if !handled {
        refreshGeometry(discover: windowID == nil)
      }
    case .leftMouseUp:
      endDrag()
      if tracksWindows { refreshGeometry(discover: true) }
    case .scrollWheel:
      let delta = abs(event.scrollingDeltaY)
      if delta > Self.minimumScrollDelta {
        emit(
          .scroll, interval: Self.scrollThrottleInterval,
          intensity: min(delta / Self.scrollIntensityScale, 1))
      }
    default: break
    }
  }

  private func endDrag() {
    dragTracker.end(canReconcile: started && isEnabled && tracksWindows && !isSuspended)
  }

  private func settle() {
    settleTimer?.invalidate()
    settleTimer = nil
    guard currentManipulation != nil else { return }
    currentManipulation = nil
    latestGeometry = nil
    emit(.windowSettled, interval: Self.settleThrottleInterval)
  }

  private func housekeeping() {
    guard isEnabled, !isSuspended else { return }
    let trusted = usesAccessibility && AXIsProcessTrusted()
    if trusted != hasAccessibility {
      hasAccessibility = trusted
      followFrontmostApplication(force: true)
      configureTimers()
      onEnvironmentChanged?()
    }
    guard let anyEventType = CGEventType(rawValue: UInt32.max) else { return }
    let elapsed = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState, eventType: anyEventType)
    let idle = elapsed > Self.userIdleThresholdSeconds
    if idle != isIdle {
      isIdle = idle
      emit(idle ? .userIdle : .userReturned)
    }
  }

  private func emit(_ kind: EventKind, interval: Double = 0, intensity: Double = 1) {
    let event = WorkspaceEvent(
      kind, at: ProcessInfo.processInfo.systemUptime, intensity: intensity)
    guard throttle.accepts(event, interval: interval) else { return }
    receivedEvents += 1
    eventCounts[kind, default: 0] += 1
    onEvent?(event)
  }

  @objc private func activated() { followFrontmostApplication() }
  @objc private func localWindowChanged(_ notification: Notification) {
    guard processID == ProcessInfo.processInfo.processIdentifier,
      let window = notification.object as? NSWindow, window.canBecomeMain,
      window.styleMask.contains(.titled), window.windowNumber > 0,
      window.isMainWindow || window.isKeyWindow || UInt32(window.windowNumber) == windowID
    else { return }
    publishGeometry(window.frame, windowID: UInt32(window.windowNumber))
  }
  @objc private func spaceChanged() { refreshGeometry(discover: true) }
  @objc private func displaysChanged() {
    refreshGeometry(discover: true)
    onGeometryChanged?()
  }
  @objc private func environmentChanged() {
    isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    onEnvironmentChanged?()
  }
  @objc private func suspend() {
    isSuspended = true
    endDrag()
    configureTimers()
    onEnvironmentChanged?()
  }
  @objc private func resume() {
    isSuspended = false
    followFrontmostApplication(force: true)
    configureTimers()
    onEnvironmentChanged?()
  }
}
