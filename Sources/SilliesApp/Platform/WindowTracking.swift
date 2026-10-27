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

enum TrackableApplicationPolicy {
  private static let systemCoreServicesPrefix = "/System/Library/CoreServices/"
  private static let systemFrameworksPrefix = "/System/Library/Frameworks/"
  private static let systemPrivateFrameworksPrefix = "/System/Library/PrivateFrameworks/"
  private static let allowedSystemBundleIdentifiers: Set<String> = [
    "com.apple.finder"
  ]

  static func isTrackable(_ application: NSRunningApplication) -> Bool {
    isTrackable(
      activationPolicy: application.activationPolicy,
      bundleIdentifier: application.bundleIdentifier,
      bundlePath: application.bundleURL?.path)
  }

  static func isTrackable(
    activationPolicy: NSApplication.ActivationPolicy,
    bundleIdentifier: String?,
    bundlePath: String?
  ) -> Bool {
    guard activationPolicy == .regular else { return false }
    if let bundleIdentifier, allowedSystemBundleIdentifiers.contains(bundleIdentifier) {
      return true
    }
    if let bundlePath {
      if bundlePath.hasPrefix(systemCoreServicesPrefix)
        || bundlePath.hasPrefix(systemFrameworksPrefix)
        || bundlePath.hasPrefix(systemPrivateFrameworksPrefix)
      {
        return false
      }
    }
    return true
  }
}

@MainActor @Observable
final class WorkspaceTracker: NSObject, WorkspaceEventProducer {
  private static let accessibilityHeartbeatInterval: Double = 1.0
  private static let pollingHeartbeatInterval: Double = 0.25
  private static let accessibilityTimerTolerance: Double = 0.15
  private static let pollingTimerTolerance: Double = 0.03
  private static let housekeepingTimerTolerance: Double = 1.0
  private static let discoveryTickMultiple = 2
  private static let followUpDiscoveryDelays: [Double] = [0.035, 0.11, 0.2, 0.35, 0.55]
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
  private static let clickSelectionExpirationSeconds: Double = 0.35
  private static let manipulationSpeedScalePointsPerSecond: Double = 1200
  private static let minimumManipulationIntensity: Double = 0.25
  private static let maximumManipulationIntensity: Double = 1.0
  private static let transitionSettleInterval: Double = 0.22
  private static let minimumTransitionHideDuration: Double = 0.18
  private static let transitionPollInterval: Double = 0.09
  private static let maxMinimizeTransitionDuration: Double = 0.60
  private static let maxAutonomousTransitionDuration: Double = 1.20
  private nonisolated static let housekeepingQueue = DispatchQueue(
    label: "app.sillies.housekeeping", qos: .utility)

  private struct AutonomousTransitionGate {
    private(set) var isActive = false
    private(set) var originWindowID: CGWindowID?
    private(set) var isMinimizingOrigin = false
    private(set) var startedAt: Double = 0
    private(set) var lastActivityAt: Double = 0
    private(set) var candidateWindowID: CGWindowID?
    private(set) var candidateFrame: CGRect?
    private(set) var candidateStableSince: Double = 0

    mutating func begin(
      originWindowID: CGWindowID?,
      minimizing: Bool,
      at now: Double
    ) {
      if !isActive {
        isActive = true
        self.originWindowID = originWindowID
        isMinimizingOrigin = minimizing
        startedAt = now
        candidateWindowID = nil
        candidateFrame = nil
        candidateStableSince = now
      } else {
        if minimizing {
          isMinimizingOrigin = true
        }
        if self.originWindowID == nil {
          self.originWindowID = originWindowID
        }
      }
      lastActivityAt = now
    }

    mutating func recordActivity(minimizing: Bool = false, at now: Double) {
      guard isActive else { return }
      if minimizing {
        isMinimizingOrigin = true
      }
      lastActivityAt = now
      candidateStableSince = now
    }

    mutating func observeCandidate(windowID: CGWindowID, frame: CGRect, at now: Double) {
      if candidateWindowID != windowID
        || candidateFrame.map({ !WindowServerSource.framesMatch($0, frame) }) != false
      {
        candidateWindowID = windowID
        candidateFrame = frame
        candidateStableSince = now
      }
    }

    mutating func clearCandidate(at now: Double) {
      candidateWindowID = nil
      candidateFrame = nil
      candidateStableSince = now
    }

    mutating func preserveAcrossApplicationSwitch(at now: Double) {
      guard isActive && isMinimizingOrigin else {
        reset()
        return
      }
      clearCandidate(at: now)
    }

    mutating func reset() {
      self = AutonomousTransitionGate()
    }
  }

  private struct ClickSelectionState {
    var point: CGPoint?
    var capturedAt: Double = 0
    var resolvedProcessID: pid_t = 0

    mutating func record(at newPoint: CGPoint, now: Double) {
      point = newPoint
      capturedAt = now
      resolvedProcessID = 0
    }

    mutating func clear() {
      point = nil
    }

    mutating func markResolved(for processID: pid_t) {
      if point != nil {
        resolvedProcessID = processID
      }
    }

    func isActive(at now: Double, expiration: Double) -> Bool {
      point != nil && now - capturedAt < expiration
    }

    func activePoint(for processID: pid_t, at now: Double, expiration: Double) -> CGPoint? {
      guard let point,
        resolvedProcessID != processID,
        now - capturedAt < expiration
      else { return nil }
      return point
    }
  }

  private(set) var hasAccessibility = false
  private(set) var applicationName = "Your desktop"
  private(set) var bundleIdentifier: String?
  @ObservationIgnored private(set) var windowFrame: CGRect?
  private(set) var windowID: CGWindowID?
  @ObservationIgnored private(set) var windowLayer: Int = WindowServerSource.normalWindowLayer
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
  @ObservationIgnored private var transitionTimer: Timer?
  @ObservationIgnored private var discoveryTasks: [DispatchWorkItem] = []
  @ObservationIgnored private var throttle = EventThrottle()
  @ObservationIgnored private var isEnabled = true
  @ObservationIgnored private var tracksWindows = true
  @ObservationIgnored private var started = false
  @ObservationIgnored private var heartbeatTicks = 0
  @ObservationIgnored private var lastGeometryTime: Double = 0
  @ObservationIgnored private var currentManipulation: EventKind?
  @ObservationIgnored private var preferredAccessibilityFrame: CGRect?
  @ObservationIgnored private var roleSnapshot: AccessibilityWindowRoleSnapshot?
  @ObservationIgnored private var clickSelection = ClickSelectionState()
  @ObservationIgnored private var transitionGate = AutonomousTransitionGate()
  @ObservationIgnored private var isLeftMouseDown = false
  @ObservationIgnored private var housekeepingInFlight = false
  @ObservationIgnored private(set) var isAwaitingApplicationWindow = false
  @ObservationIgnored private let usesAccessibility: Bool

  private var isLeftMouseButtonPressed: Bool {
    guard isLeftMouseDown else { return false }
    if CGEventSource.buttonState(.combinedSessionState, button: .left) {
      return true
    }
    isLeftMouseDown = false
    return false
  }

  var isManipulatingWindow: Bool {
    windowID != nil && (dragTracker.isDragging || currentManipulation != nil)
  }

  private var isActivelyManipulatingTrackedWindow: Bool {
    guard windowID != nil else { return false }
    return dragTracker.isDragging
      || (isLeftMouseButtonPressed
        && (dragTracker.isResizeCandidate || currentManipulation != nil))
  }

  private var isForeignAutonomousTransitionEligible: Bool {
    tracksWindows
      && processID != 0
      && processID != ProcessInfo.processInfo.processIdentifier
      && !isActivelyManipulatingTrackedWindow
      && !isLeftMouseButtonPressed
  }

  init(useAccessibility: Bool = true) {
    usesAccessibility = useAccessibility
    super.init()
    hasAccessibility = useAccessibility && AXIsProcessTrusted()
    dragTracker.onPresentFrame = { [weak self] frame in
      guard let self else { return }
      self.publishGeometry(frame, windowID: self.windowID, windowLayer: self.windowLayer)
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
    for name in [
      NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didUnhideApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ] {
      center.addObserver(
        self, selector: #selector(applicationVisibilityChanged), name: name, object: nil)
    }
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
      NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
      NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
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
    cancelAutonomousTransition()
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

  func simulateTrackedWindow(
    _ frame: CGRect?,
    windowID: CGWindowID?,
    windowLayer: Int = WindowServerSource.normalWindowLayer
  ) {
    isAwaitingApplicationWindow = false
    publishGeometry(frame, windowID: windowID, windowLayer: windowLayer)
  }

  func simulateApplicationSwitchInFlight(
    processID: pid_t,
    applicationName: String = "Simulated App",
    bundleIdentifier: String? = nil
  ) {
    let hadTrackedWindow = windowID != nil || windowFrame != nil
    dragTracker.invalidateSession()
    self.processID = processID
    self.applicationName = applicationName
    self.bundleIdentifier = bundleIdentifier
    windowID = nil
    windowLayer = WindowServerSource.normalWindowLayer
    latestGeometry = nil
    preferredAccessibilityFrame = nil
    roleSnapshot = nil
    isAwaitingApplicationWindow = isEnabled && tracksWindows && hadTrackedWindow
    onApplicationChanged?()
  }

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
      cancelAutonomousTransition()
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
      timer.tolerance =
        hasAccessibility ? Self.accessibilityTimerTolerance : Self.pollingTimerTolerance
      RunLoop.main.add(timer, forMode: .common)
      heartbeat = timer
    }
    idleTimer = Timer.scheduledTimer(
      withTimeInterval: Self.housekeepingInterval, repeats: true
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.housekeeping() }
    }
    idleTimer?.tolerance = Self.housekeepingTimerTolerance
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
    if !force && processID == app.processIdentifier { return }
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      guard
        NSApp.windows.contains(where: {
          $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain && $0.styleMask.contains(.titled)
        })
      else { return }
    } else {
      guard TrackableApplicationPolicy.isTrackable(app) else { return }
    }
    guard force || processID != app.processIdentifier else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if force {
      cancelAutonomousTransition()
    } else {
      transitionGate.preserveAcrossApplicationSwitch(at: now)
      if !transitionGate.isActive {
        transitionTimer?.invalidate()
        transitionTimer = nil
      }
    }
    let hadTrackedWindow = (windowID != nil || windowFrame != nil) && !transitionGate.isActive
    dragTracker.invalidateSession()
    processID = app.processIdentifier
    applicationName = app.localizedName ?? "Your app"
    bundleIdentifier = app.bundleIdentifier
    windowID = nil
    windowLayer = WindowServerSource.normalWindowLayer
    latestGeometry = nil
    preferredAccessibilityFrame = nil
    roleSnapshot = nil
    isAwaitingApplicationWindow = isEnabled && tracksWindows && hadTrackedWindow
    if isEnabled && tracksWindows {
      if hasAccessibility {
        accessibilitySource?.observe(processID: processID)
      } else {
        refreshGeometry(discover: true)
      }
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
    for (index, delay) in Self.followUpDiscoveryDelays.enumerated() {
      let task = DispatchWorkItem { [weak self] in
        MainActor.assumeIsolated {
          guard let self, !self.isActivelyManipulatingTrackedWindow else { return }
          self.followFrontmostApplication()
          if self.hasAccessibility && index >= 2 {
            self.accessibilitySource?.refresh()
          }
          if !self.hasAccessibility || self.roleSnapshot != nil || index > 0 {
            self.refreshGeometry(discover: true)
          }
        }
      }
      discoveryTasks.append(task)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
  }

  private func refreshGeometry(discover: Bool = false) {
    guard started, isEnabled, tracksWindows, !isSuspended, processID != 0 else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let lockedToCurrentWindow = isActivelyManipulatingTrackedWindow
    let activeClickPoint =
      lockedToCurrentWindow
      ? nil
      : clickSelection.activePoint(
        for: processID, at: now, expiration: Self.clickSelectionExpirationSeconds)
    geometrySource?.refresh(
      WindowServerSource.Request(
        processID: processID,
        windowID: windowID,
        discover: lockedToCurrentWindow ? false : discover,
        preferredFrame: lockedToCurrentWindow ? nil : preferredAccessibilityFrame,
        preferredPoint: activeClickPoint,
        roleSnapshot: roleSnapshot,
        requiresVerifiedFloatingRole: hasAccessibility,
        isManipulatingWindow: isActivelyManipulatingTrackedWindow))
  }

  private func accept(_ observation: WindowServerObservation) {
    guard observation.processID == processID, isEnabled, !isSuspended else { return }
    let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
    let priorInputFrames = inputWindowFrames
    updateBackgroundAndInputFrames(from: observation, primaryScreenTop: primaryScreenTop)
    guard tracksWindows else {
      cancelAutonomousTransition()
      isAwaitingApplicationWindow = false
      return
    }
    let wasAwaitingApplicationWindow = isAwaitingApplicationWindow
    isAwaitingApplicationWindow = false
    geometryReads += 1
    let resolved = resolveTrackedWindow(from: observation, primaryScreenTop: primaryScreenTop)
    let wasReconcilingRelease = dragTracker.hasActiveSession && !dragTracker.isDragging
    let now = ProcessInfo.processInfo.systemUptime
    if dragTracker.hasActiveSession {
      let decision = dragTracker.validate(
        observationFrame: resolved.frame,
        matchesTrackedWindow: resolved.windowID == windowID,
        currentFrame: windowFrame,
        capturedAt: observation.capturedAt,
        now: now)
      if decision == .ignore || decision == .usePointer {
        return
      }
    }
    if shouldHoldAutonomousTransition(
      resolvedWindowID: resolved.windowID,
      resolvedFrame: resolved.frame,
      priorInputFrames: priorInputFrames,
      at: now)
    {
      return
    }
    let previousFrame = windowFrame
    let previousID = windowID
    publishGeometry(
      resolved.frame,
      windowID: resolved.windowID,
      windowLayer: observation.windowLayer,
      suppressManipulationEvent: wasReconcilingRelease)
    if wasReconcilingRelease && !dragTracker.hasActiveSession {
      settle()
    }
    if wasAwaitingApplicationWindow && resolved.windowID == nil && previousFrame == nil
      && previousID == nil
    {
      onGeometryChanged?()
    }
    dragTracker.attachCandidateIfNeeded(
      frame: windowFrame, hasWindow: windowID != nil, isLowPower: isLowPower)
  }

  private func beginAutonomousTransition(
    originWindowID: CGWindowID?,
    minimizing: Bool,
    at now: Double
  ) {
    if !dragTracker.isDragging {
      dragTracker.invalidateSession()
    }
    settleTimer?.invalidate()
    settleTimer = nil
    currentManipulation = nil
    transitionGate.begin(originWindowID: originWindowID, minimizing: minimizing, at: now)
    if windowID != nil || windowFrame != nil {
      publishGeometry(nil, windowID: nil, suppressManipulationEvent: true)
    }
    scheduleTransitionPoll()
  }

  private func cancelAutonomousTransition() {
    transitionTimer?.invalidate()
    transitionTimer = nil
    transitionGate.reset()
  }

  private func scheduleTransitionPoll() {
    guard transitionTimer == nil, started, isEnabled, tracksWindows, !isSuspended else { return }
    let timer = Timer(timeInterval: Self.transitionPollInterval, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.transitionTimer = nil
        guard self.transitionGate.isActive, !self.isActivelyManipulatingTrackedWindow else {
          return
        }
        self.followFrontmostApplication()
        if self.hasAccessibility {
          self.accessibilitySource?.refresh(reason: AccessibilityWindowSource.sampleReason)
        }
        self.refreshGeometry(discover: true)
        if self.transitionGate.isActive {
          self.scheduleTransitionPoll()
        }
      }
    }
    transitionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func shouldHoldAutonomousTransition(
    resolvedWindowID: CGWindowID?,
    resolvedFrame: CGRect?,
    priorInputFrames: [Int: CGRect],
    at now: Double
  ) -> Bool {
    let canTrackForeignTransition =
      tracksWindows
      && !isActivelyManipulatingTrackedWindow
      && processID != 0
      && processID != ProcessInfo.processInfo.processIdentifier
    guard canTrackForeignTransition else {
      if transitionGate.isActive {
        cancelAutonomousTransition()
      }
      return false
    }
    if !transitionGate.isActive {
      guard isForeignAutonomousTransitionEligible && !dragTracker.hasActiveSession else {
        return false
      }
      return beginAutonomousTransitionIfNeeded(
        resolvedWindowID: resolvedWindowID,
        resolvedFrame: resolvedFrame,
        priorInputFrames: priorInputFrames,
        at: now)
    }
    return evaluateActiveAutonomousTransition(
      resolvedWindowID: resolvedWindowID,
      resolvedFrame: resolvedFrame,
      priorInputFrames: priorInputFrames,
      at: now)
  }

  private func beginAutonomousTransitionIfNeeded(
    resolvedWindowID: CGWindowID?,
    resolvedFrame: CGRect?,
    priorInputFrames: [Int: CGRect],
    at now: Double
  ) -> Bool {
    if let currentID = windowID, let currentFrame = windowFrame {
      guard let nextID = resolvedWindowID, let nextFrame = resolvedFrame else {
        let isStillOnScreen = inputWindowFrames[Int(currentID)] != nil
        let isRemovedFromStandardWindows =
          roleSnapshot?.hasVerifiedWindowList == true
          && !(roleSnapshot?.standardWindowFrames.contains(where: {
            WindowServerSource.framesMatch($0, currentFrame)
          }) ?? false)
        if isStillOnScreen || isRemovedFromStandardWindows {
          beginAutonomousTransition(
            originWindowID: currentID,
            minimizing: isRemovedFromStandardWindows || isStillOnScreen,
            at: now)
          return true
        }
        return false
      }
      if nextID == currentID {
        guard !WindowServerSource.framesMatch(currentFrame, nextFrame) else { return false }
        beginAutonomousTransition(originWindowID: currentID, minimizing: false, at: now)
        transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
        return true
      }
      if let latestOriginFrame = inputWindowFrames[Int(currentID)] {
        let originFrameChanged = !WindowServerSource.framesMatch(currentFrame, latestOriginFrame)
        let originRemovedFromAX =
          roleSnapshot?.hasVerifiedWindowList == true
          && !(roleSnapshot?.standardWindowFrames.contains(where: {
            WindowServerSource.framesMatch($0, currentFrame)
          }) ?? false)
        if originFrameChanged || originRemovedFromAX {
          beginAutonomousTransition(originWindowID: currentID, minimizing: true, at: now)
          transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
          return true
        }
      }
      return false
    }
    if let nextID = resolvedWindowID,
      let nextFrame = resolvedFrame,
      let priorFrame = priorInputFrames[Int(nextID)],
      !WindowServerSource.framesMatch(priorFrame, nextFrame)
    {
      beginAutonomousTransition(originWindowID: nextID, minimizing: false, at: now)
      transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
      return true
    }
    return false
  }

  private func evaluateActiveAutonomousTransition(
    resolvedWindowID: CGWindowID?,
    resolvedFrame: CGRect?,
    priorInputFrames: [Int: CGRect],
    at now: Double
  ) -> Bool {
    if now - transitionGate.startedAt >= Self.maxAutonomousTransitionDuration {
      cancelAutonomousTransition()
      return false
    }
    if let originID = transitionGate.originWindowID,
      let currentOriginFrame = inputWindowFrames[Int(originID)],
      let priorOriginFrame = priorInputFrames[Int(originID)],
      !WindowServerSource.framesMatch(priorOriginFrame, currentOriginFrame),
      resolvedWindowID == nil || resolvedWindowID == originID
    {
      transitionGate.recordActivity(at: now)
    }
    guard let nextID = resolvedWindowID, let nextFrame = resolvedFrame else {
      if let originID = transitionGate.originWindowID,
        inputWindowFrames[Int(originID)] == nil,
        roleSnapshot?.hasVerifiedWindowList == true,
        roleSnapshot?.standardWindowFrames.isEmpty == true,
        now - transitionGate.lastActivityAt >= Self.transitionSettleInterval
      {
        cancelAutonomousTransition()
        return false
      }
      transitionGate.clearCandidate(at: now)
      scheduleTransitionPoll()
      return true
    }
    if transitionGate.isMinimizingOrigin,
      nextID == transitionGate.originWindowID,
      now - transitionGate.startedAt < Self.maxMinimizeTransitionDuration
    {
      scheduleTransitionPoll()
      return true
    }
    if transitionGate.isMinimizingOrigin,
      let originID = transitionGate.originWindowID,
      nextID != originID,
      inputWindowFrames[Int(originID)] != nil,
      now - transitionGate.startedAt < Self.maxMinimizeTransitionDuration
    {
      transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
      scheduleTransitionPoll()
      return true
    }
    let matchesPriorInput =
      priorInputFrames[Int(nextID)].map { WindowServerSource.framesMatch($0, nextFrame) } ?? false
    if let priorNextFrame = priorInputFrames[Int(nextID)],
      !WindowServerSource.framesMatch(priorNextFrame, nextFrame)
    {
      transitionGate.recordActivity(at: now)
      transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
      scheduleTransitionPoll()
      return true
    }
    let matchesCandidate =
      transitionGate.candidateWindowID == nextID
      && transitionGate.candidateFrame.map({ WindowServerSource.framesMatch($0, nextFrame) })
        == true
    transitionGate.observeCandidate(windowID: nextID, frame: nextFrame, at: now)
    let stableElapsed = now - transitionGate.candidateStableSince
    let quietElapsed = now - transitionGate.lastActivityAt
    let totalElapsed = now - transitionGate.startedAt
    let isSettledReplacementWindow =
      transitionGate.isMinimizingOrigin
      && nextID != transitionGate.originWindowID
      && matchesPriorInput
      && totalElapsed >= Self.minimumTransitionHideDuration
    if isSettledReplacementWindow
      || (matchesCandidate
        && stableElapsed >= Self.transitionSettleInterval
        && quietElapsed >= Self.transitionSettleInterval
        && totalElapsed >= Self.minimumTransitionHideDuration)
    {
      cancelAutonomousTransition()
      return false
    }
    scheduleTransitionPoll()
    return true
  }

  private func updateBackgroundAndInputFrames(
    from observation: WindowServerObservation,
    primaryScreenTop: CGFloat
  ) {
    if let ids = observation.backgroundWindowIDs {
      backgroundWindowIDs = ids
      preferredAccessibilityFrame = nil
      clickSelection.markResolved(for: processID)
    }
    if let frames = observation.inputWindowFrames {
      inputWindowFrames = frames.mapValues {
        ScreenCoordinates.appKitRect(fromAccessibility: $0, primaryScreenTop: primaryScreenTop)
      }
    }
  }

  private func resolveTrackedWindow(
    from observation: WindowServerObservation,
    primaryScreenTop: CGFloat
  ) -> (windowID: CGWindowID?, frame: CGRect?) {
    var next = observation.frame.map {
      ScreenCoordinates.appKitRect(fromAccessibility: $0, primaryScreenTop: primaryScreenTop)
    }
    var resolvedWindowID = observation.windowID
    if let id = resolvedWindowID, let next { inputWindowFrames[Int(id)] = next }
    // Native windows already provide synchronous bounds. Never overwrite them with stale IPC readback.
    if processID == ProcessInfo.processInfo.processIdentifier,
      let id = resolvedWindowID ?? windowID,
      let native = NSApp.window(withWindowNumber: Int(id)),
      native.isVisible, !native.isMiniaturized
    {
      resolvedWindowID = id
      next = native.frame
    }
    return (resolvedWindowID, next)
  }

  private func publishGeometry(
    _ next: CGRect?,
    windowID nextID: CGWindowID?,
    windowLayer nextLayer: Int = WindowServerSource.normalWindowLayer,
    suppressManipulationEvent: Bool = false
  ) {
    let old = windowFrame
    let previousID = windowID
    let previousLayer = windowLayer
    guard old != next || previousID != nextID || previousLayer != nextLayer else { return }
    let time = ProcessInfo.processInfo.systemUptime
    windowFrame = next
    if windowID != nextID { windowID = nextID }
    windowLayer = nextID == nil ? WindowServerSource.normalWindowLayer : nextLayer
    latestGeometry = nil
    if !suppressManipulationEvent, let old, let next, previousID == nextID {
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
        let scaledSpeed = speed / Self.manipulationSpeedScalePointsPerSecond
        let intensity = min(
          max(scaledSpeed, Self.minimumManipulationIntensity),
          Self.maximumManipulationIntensity)
        emit(kind, intensity: intensity)
      }
      if !dragTracker.isDragging && !isLeftMouseButtonPressed {
        settleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.settleDelaySeconds, repeats: false) { [weak self] _ in
          MainActor.assumeIsolated { self?.settle() }
        }
        settleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
      }
    } else if !suppressManipulationEvent, currentManipulation != nil {
      settleTimer?.invalidate()
      settleTimer = nil
      currentManipulation = nil
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
    if let snapshot = observation.roleSnapshot {
      roleSnapshot = snapshot
      WindowTargetMetadata.shared.seedRoleSnapshot(snapshot, for: processID)
    }
    let isWindowRemovedNotification =
      observation.reason == kAXUIElementDestroyedNotification
      || observation.reason == kAXWindowMiniaturizedNotification
    let isFocusChangedNotification =
      observation.reason == kAXFocusedWindowChangedNotification
      || observation.reason == kAXMainWindowChangedNotification
    if isWindowRemovedNotification {
      clickSelection.clear()
      if !dragTracker.isDragging {
        dragTracker.invalidateSession()
      }
    }
    if (isWindowRemovedNotification || isFocusChangedNotification) && !dragTracker.isDragging {
      settleTimer?.invalidate()
      settleTimer = nil
      currentManipulation = nil
    }
    let isWindowLifecycleNotification =
      isWindowRemovedNotification
      || observation.reason == kAXWindowDeminiaturizedNotification
      || observation.reason == kAXWindowCreatedNotification
    let now = ProcessInfo.processInfo.systemUptime
    let hasActiveClickSelection = clickSelection.isActive(
      at: now, expiration: Self.clickSelectionExpirationSeconds)
    if !isActivelyManipulatingTrackedWindow,
      let focusedFrame = observation.focusedFrame,
      !hasActiveClickSelection
    {
      preferredAccessibilityFrame = focusedFrame
    }
    let discover =
      !isActivelyManipulatingTrackedWindow
      && (observation.reason == AccessibilityWindowSource.activationReason
        || observation.reason == AccessibilityWindowSource.sampleReason
        || isFocusChangedNotification
        || isWindowLifecycleNotification)
    let isGeometryNotification =
      observation.reason == kAXMovedNotification
      || observation.reason == kAXResizedNotification
    if !dragTracker.isDragging
      && tracksWindows
      && processID != 0
      && processID != ProcessInfo.processInfo.processIdentifier
    {
      if observation.reason == kAXWindowMiniaturizedNotification {
        beginAutonomousTransition(originWindowID: windowID, minimizing: true, at: now)
      } else if observation.reason == kAXWindowDeminiaturizedNotification {
        beginAutonomousTransition(originWindowID: windowID, minimizing: false, at: now)
      } else if isGeometryNotification
        && isForeignAutonomousTransitionEligible
        && !dragTracker.hasActiveSession
        && (windowID != nil || transitionGate.isActive)
      {
        beginAutonomousTransition(originWindowID: windowID, minimizing: false, at: now)
      }
    }
    if !(isGeometryNotification && dragTracker.isPointerConfirmed) {
      refreshGeometry(discover: discover)
      if isWindowLifecycleNotification && !isActivelyManipulatingTrackedWindow {
        scheduleFollowUpDiscovery()
      }
    }
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
      handleMouseDown(event, at: now)
    case .leftMouseDragged:
      handleMouseDragged(at: now)
    case .leftMouseUp:
      handleMouseUp()
    case .scrollWheel:
      handleScroll(event)
    default: break
    }
  }

  private func handleMouseDown(_ event: NSEvent, at now: Double) {
    guard tracksWindows else { return }
    isLeftMouseDown = true
    settleTimer?.invalidate()
    settleTimer = nil
    currentManipulation = nil
    let eventPoint = event.cgEvent?.location
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let point =
      eventPoint.map { CGPoint(x: $0.x, y: top - $0.y) }
      ?? NSEvent.mouseLocation
    preferredAccessibilityFrame = nil
    followFrontmostApplication()
    dragTracker.beginCandidate(
      frame: windowFrame, hasWindow: windowID != nil, pointer: point, at: now,
      centered: event.modifierFlags.contains(.option),
      proportional: event.modifierFlags.contains(.shift),
      isLowPower: isLowPower)
    if dragTracker.isResizeCandidate {
      clickSelection.clear()
      cancelFollowUpDiscovery()
      refreshGeometry(discover: false)
      return
    }
    clickSelection.record(at: eventPoint ?? CGPoint(x: point.x, y: top - point.y), now: now)
    refreshGeometry(discover: !dragTracker.hasActiveSession)
    scheduleFollowUpDiscovery()
  }

  private func handleMouseDragged(at now: Double) {
    guard tracksWindows else { return }
    isLeftMouseDown = true
    settleTimer?.invalidate()
    settleTimer = nil
    let handled = dragTracker.updateDrag(
      frame: windowFrame, hasWindow: windowID != nil, at: now, isLowPower: isLowPower)
    if handled && windowID != nil {
      clickSelection.clear()
      cancelFollowUpDiscovery()
    } else {
      refreshGeometry(discover: windowID == nil || clickSelection.point != nil)
    }
  }

  private func handleMouseUp() {
    let wasDragging = dragTracker.isDragging && dragTracker.isPointerConfirmed
    isLeftMouseDown = false
    clickSelection.clear()
    endDrag()
    guard tracksWindows else { return }
    if !wasDragging {
      accessibilitySource?.refresh()
      refreshGeometry(discover: true)
      scheduleFollowUpDiscovery()
    } else {
      accessibilitySource?.refresh(reason: AccessibilityWindowSource.sampleReason)
      refreshGeometry(discover: windowID == nil)
    }
  }

  private func handleScroll(_ event: NSEvent) {
    let delta = abs(event.scrollingDeltaY)
    if delta > Self.minimumScrollDelta {
      emit(
        .scroll, interval: Self.scrollThrottleInterval,
        intensity: min(delta / Self.scrollIntensityScale, 1))
    }
  }

  private func endDrag() {
    isLeftMouseDown = false
    dragTracker.end(canReconcile: started && isEnabled && tracksWindows && !isSuspended)
    if currentManipulation != nil && !dragTracker.hasActiveSession {
      settle()
    }
  }

  private func settle() {
    settleTimer?.invalidate()
    settleTimer = nil
    guard currentManipulation != nil else { return }
    currentManipulation = nil
    latestGeometry = nil
    if hasAccessibility {
      accessibilitySource?.refresh(reason: AccessibilityWindowSource.sampleReason)
    }
    emit(.windowSettled, interval: Self.settleThrottleInterval)
  }

  private func housekeeping() {
    guard isEnabled, !isSuspended, !housekeepingInFlight else { return }
    housekeepingInFlight = true
    let checkAccessibility = usesAccessibility
    Self.housekeepingQueue.async { [weak self] in
      let trusted = checkAccessibility && AXIsProcessTrusted()
      let elapsed: Double? = CGEventType(rawValue: UInt32.max).map {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
      }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.housekeepingInFlight = false
        guard self.isEnabled, !self.isSuspended else { return }
        if trusted != self.hasAccessibility {
          self.hasAccessibility = trusted
          self.followFrontmostApplication(force: true)
          self.configureTimers()
          self.onEnvironmentChanged?()
        }
        guard let elapsed else { return }
        let idle = elapsed > Self.userIdleThresholdSeconds
        if idle != self.isIdle {
          self.isIdle = idle
          self.emit(idle ? .userIdle : .userReturned)
        }
      }
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
  @objc private func applicationVisibilityChanged() {
    followFrontmostApplication()
    if hasAccessibility { accessibilitySource?.refresh() }
    refreshGeometry(discover: true)
    scheduleFollowUpDiscovery()
  }
  @objc private func localWindowChanged(_ notification: Notification) {
    guard processID == ProcessInfo.processInfo.processIdentifier,
      let window = notification.object as? NSWindow, window.canBecomeMain,
      window.styleMask.contains(.titled), window.windowNumber > 0
    else { return }
    if notification.name == NSWindow.willCloseNotification
      || notification.name == NSWindow.willMiniaturizeNotification
      || notification.name == NSWindow.didMiniaturizeNotification
    {
      if UInt32(window.windowNumber) == windowID {
        publishGeometry(nil, windowID: nil)
      }
      refreshGeometry(discover: true)
      scheduleFollowUpDiscovery()
      return
    }
    guard window.isMainWindow || window.isKeyWindow || UInt32(window.windowNumber) == windowID
    else { return }
    if notification.name == NSWindow.didMoveNotification
      || notification.name == NSWindow.didResizeNotification
    {
      roleSnapshot?.hasExactStandardWindowFrames = false
    }
    publishGeometry(window.frame, windowID: UInt32(window.windowNumber))
  }
  @objc private func spaceChanged() {
    followFrontmostApplication()
    if hasAccessibility { accessibilitySource?.refresh() }
    refreshGeometry(discover: true)
    scheduleFollowUpDiscovery()
  }
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
