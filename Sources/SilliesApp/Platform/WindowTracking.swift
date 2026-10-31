import AppKit
import ApplicationServices
import Observation
import QuartzCore
import SilliesCore

@MainActor @Observable
final class WorkspaceTracker: WorkspaceEventProducer {
  enum Accessibility { case enabled, disabled }
  private enum GeometryPublication { case manipulation, reconciliation }
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
  private static let transitionPollInterval: Double = 0.09
  private nonisolated static let housekeepingQueue = DispatchQueue(
    label: "app.sillies.housekeeping", qos: .utility)

  private(set) var hasAccessibility = false
  var applicationName: String { focus.application.name }
  var bundleIdentifier: String? { focus.application.bundleIdentifier }
  @ObservationIgnored private(set) var windowFrame: CGRect?
  private(set) var windowID: CGWindowID?
  @ObservationIgnored private(set) var windowLayer: Int = WindowServerSource.normalWindowLayer
  var processID: pid_t { focus.application.processID }
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
  @ObservationIgnored private let inputMonitor = WorkspaceInputMonitor()
  @ObservationIgnored private let focus = WorkspaceFocusSession()
  @ObservationIgnored private var notifications: WorkspaceNotifications?
  @ObservationIgnored private let schedule = WindowTrackingSchedule()
  @ObservationIgnored private var throttle = EventThrottle()
  @ObservationIgnored private var isEnabled = true
  @ObservationIgnored private var tracksWindows = true
  @ObservationIgnored private var started = false
  @ObservationIgnored private var observationGeneration = UUID()
  @ObservationIgnored private var heartbeatTicks = 0
  @ObservationIgnored private var lastGeometryTime: Double = 0
  @ObservationIgnored private var currentManipulation: EventKind?
  @ObservationIgnored private var preferredAccessibilityFrame: CGRect?
  @ObservationIgnored private var roleSnapshot: AccessibilityWindowRoleSnapshot?
  @ObservationIgnored private var clickSelection = WindowClickSelection()
  @ObservationIgnored private var transitionGate = WindowTransitionState()
  @ObservationIgnored private var minimizingNativeWindowIDs: Set<Int> = []
  @ObservationIgnored private var isLeftMouseDown = false
  @ObservationIgnored private var housekeepingInFlight = false
  var isAwaitingApplicationWindow: Bool { focus.isAwaitingWindow }
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

  init(accessibility: Accessibility = .enabled) {
    usesAccessibility = accessibility == .enabled
    hasAccessibility = usesAccessibility && AXIsProcessTrusted()
    dragTracker.onPresentFrame = { [weak self] frame in
      guard let self else { return }
      self.publishGeometry(frame, windowID: self.windowID, windowLayer: self.windowLayer)
    }
    dragTracker.onRequestGeometryRefresh = { [weak self] in
      self?.refreshGeometry()
    }
    dragTracker.onDragStarted = { [weak self] in
      self?.schedule.cancel(.settle)
    }
    dragTracker.onEnded = { [weak self] in
      self?.schedule.cancel(.settle)
      self?.settle()
    }
  }

  func start() {
    guard !started else { return }
    started = true
    let generation = UUID()
    observationGeneration = generation
    updateMetadataWorkerActivity()
    geometrySource = WindowServerSource { [weak self] value in
      MainRunLoopDelivery.perform { [weak self] in
        guard let self, self.observationGeneration == generation else { return }
        self.accept(value)
      }
    }
    accessibilitySource = AccessibilityWindowSource { [weak self] value in
      MainRunLoopDelivery.perform { [weak self] in
        guard let self, self.observationGeneration == generation else { return }
        self.acceptAccessibility(value)
      }
    }
    let notifications = WorkspaceNotifications { [weak self] in self?.receiveNotification($0) }
    self.notifications = notifications
    notifications.start()
    followFrontmostApplication(.reconcileCurrent)
    configureTimers()
  }

  func stop() {
    started = false
    observationGeneration = UUID()
    housekeepingInFlight = false
    WindowMetadataReader.stop(owner: ObjectIdentifier(self))
    minimizingNativeWindowIDs.removeAll()
    accessibilitySource?.stop()
    accessibilitySource = nil
    geometrySource = nil
    removeInputMonitors()
    cancelFollowUpDiscovery()
    cancelAutonomousTransition()
    dragTracker.cancel()
    schedule.stop()
    notifications?.stop()
    notifications = nil
  }

  func configure(enabled: Bool, tracksWindows: Bool) {
    guard enabled != isEnabled || tracksWindows != self.tracksWindows else { return }
    isEnabled = enabled
    self.tracksWindows = tracksWindows
    endDrag()
    if enabled && tracksWindows {
      followFrontmostApplication(.reconcileCurrent)
    } else {
      accessibilitySource?.stop()
    }
    configureTimers()
  }

  func requestAccessibility() {
    hasAccessibility = AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    if hasAccessibility { followFrontmostApplication(.reconcileCurrent) }
    configureTimers()
  }

  func refreshFocus() { followFrontmostApplication(.reconcileCurrent) }

  func simulateTrackedWindow(
    _ frame: CGRect?,
    windowID: CGWindowID?,
    windowLayer: Int = WindowServerSource.normalWindowLayer
  ) {
    focus.resolvedWindow()
    publishGeometry(frame, windowID: windowID, windowLayer: windowLayer)
  }

  func simulateApplicationSwitchInFlight(
    processID: pid_t,
    applicationName: String = "Simulated App",
    bundleIdentifier: String? = nil
  ) {
    resetApplicationWindow(
      .init(processID: processID, name: applicationName, bundleIdentifier: bundleIdentifier),
      continuity: isEnabled && tracksWindows && (windowID != nil || windowFrame != nil)
        ? .preserveUntilDiscovery : .noPreviousWindow)
    onApplicationChanged?()
  }

  func refreshInputBackgrounds() {
    guard started, isEnabled, !isSuspended, !tracksWindows, backgroundWindowIDs.isEmpty else {
      return
    }
    geometrySource?.refresh(.init(processID: processID, windowID: nil, scope: .applicationWindows))
  }

  func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  private func updateMetadataWorkerActivity() {
    if started, isEnabled, !isSuspended {
      WindowMetadataReader.start(owner: ObjectIdentifier(self))
    } else {
      WindowMetadataReader.stop(owner: ObjectIdentifier(self))
    }
  }

  private func configureTimers() {
    updateMetadataWorkerActivity()
    schedule.cancel(.heartbeat)
    schedule.cancel(.housekeeping)
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
      schedule.repeating(
        .heartbeat,
        cadence: .init(
          interval: interval,
          tolerance: hasAccessibility
            ? Self.accessibilityTimerTolerance : Self.pollingTimerTolerance)
      ) { [weak self] in
        guard let self, !self.dragTracker.isDragging else { return }
        self.followFrontmostApplication()
        self.heartbeatTicks += 1
        let needsDiscovery =
          self.windowID == nil || self.heartbeatTicks.isMultiple(of: Self.discoveryTickMultiple)
        self.refreshGeometry(scope: needsDiscovery ? .applicationWindows : .trackedWindow)
      }
    }
    schedule.repeating(
      .housekeeping,
      cadence: .init(
        interval: Self.housekeepingInterval, tolerance: Self.housekeepingTimerTolerance,
        mode: .default)
    ) { [weak self] in self?.housekeeping() }
  }

  private func installInputMonitorsIfNeeded() {
    inputMonitor.start(
      receive: { [weak self] in self?.input($0) }, released: { [weak self] in self?.endDrag() })
  }

  private func removeInputMonitors() { inputMonitor.stop() }

  private func followFrontmostApplication(
    _ refresh: WorkspaceFocusSession.Refresh = .applicationChanged
  ) {
    guard let app = focus.frontmostReplacement(for: refresh) else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if refresh == .reconcileCurrent {
      cancelAutonomousTransition()
    } else {
      transitionGate.preserveAcrossApplicationSwitch(at: now)
      if !transitionGate.isActive {
        schedule.cancel(.transition)
      }
    }
    let hadTrackedWindow = (windowID != nil || windowFrame != nil) && !transitionGate.isActive
    resetApplicationWindow(
      app,
      continuity: isEnabled && tracksWindows && hadTrackedWindow
        ? .preserveUntilDiscovery : .noPreviousWindow)
    if isEnabled && tracksWindows {
      if hasAccessibility {
        accessibilitySource?.observe(processID: processID)
      } else {
        refreshGeometry(scope: .applicationWindows)
      }
      scheduleFollowUpDiscovery()
    }
    onApplicationChanged?()
  }

  private func resetApplicationWindow(
    _ application: WorkspaceFocusSession.Application, continuity: WorkspaceFocusSession.Continuity
  ) {
    dragTracker.invalidateSession()
    focus.follow(application, continuity: continuity)
    windowID = nil
    windowLayer = WindowServerSource.normalWindowLayer
    latestGeometry = nil
    preferredAccessibilityFrame = nil
    roleSnapshot = nil
  }

  private func cancelFollowUpDiscovery() { schedule.cancelDiscoveries() }

  private func scheduleFollowUpDiscovery() {
    cancelFollowUpDiscovery()
    guard started, isEnabled, tracksWindows, !isSuspended else { return }
    for (index, delay) in Self.followUpDiscoveryDelays.enumerated() {
      schedule.once(.discovery(index), after: delay) { [weak self] in
        guard let self, !self.isActivelyManipulatingTrackedWindow else { return }
        self.followFrontmostApplication()
        if self.hasAccessibility && index >= 2 { self.accessibilitySource?.refresh() }
        if !self.hasAccessibility || self.roleSnapshot != nil || index > 0 {
          self.refreshGeometry(scope: .applicationWindows)
        }
      }
    }
  }

  private func refreshGeometry(scope: WindowRefreshScope = .trackedWindow) {
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
        scope: lockedToCurrentWindow ? .trackedWindow : scope,
        preferredFrame: lockedToCurrentWindow ? nil : preferredAccessibilityFrame,
        preferredPoint: activeClickPoint,
        roleSnapshot: roleSnapshot,
        requiresVerifiedFloatingRole: hasAccessibility,
        isManipulatingWindow: isActivelyManipulatingTrackedWindow))
  }

  private func accept(_ observation: WindowServerObservation) {
    guard started, observation.processID == processID, isEnabled, !isSuspended else { return }
    if let id = observation.windowID,
      WindowTrackingExclusions.excludesSurface(id, ownerPID: observation.processID)
    {
      return
    }
    let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
    let priorInputFrames = inputWindowFrames
    updateBackgroundAndInputFrames(from: observation, primaryScreenTop: primaryScreenTop)
    guard tracksWindows else {
      cancelAutonomousTransition()
      focus.resolvedWindow()
      return
    }
    let wasAwaitingApplicationWindow = isAwaitingApplicationWindow
    focus.resolvedWindow()
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
      publication: wasReconcilingRelease ? .reconciliation : .manipulation)
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
    reason: WindowTransitionState.Reason,
    at now: Double
  ) {
    if !dragTracker.isDragging {
      dragTracker.invalidateSession()
    }
    schedule.cancel(.settle)
    currentManipulation = nil
    transitionGate.begin(originWindowID: originWindowID, reason: reason, at: now)
    if windowID != nil || windowFrame != nil {
      publishGeometry(nil, windowID: nil, publication: .reconciliation)
    }
    scheduleTransitionPoll()
  }

  private func cancelAutonomousTransition() {
    schedule.cancel(.transition)
    transitionGate.reset()
  }

  private func scheduleTransitionPoll() {
    guard !schedule.contains(.transition), started, isEnabled, tracksWindows, !isSuspended else {
      return
    }
    schedule.once(.transition, after: Self.transitionPollInterval) { [weak self] in
      guard let self, self.transitionGate.isActive, !self.isActivelyManipulatingTrackedWindow else {
        return
      }
      self.followFrontmostApplication()
      if self.hasAccessibility {
        self.accessibilitySource?.refresh(reason: AccessibilityWindowSource.sampleReason)
      }
      self.refreshGeometry(scope: .applicationWindows)
      if self.transitionGate.isActive { self.scheduleTransitionPoll() }
    }
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
    let observation = transitionObservation(
      resolvedWindowID: resolvedWindowID, resolvedFrame: resolvedFrame,
      priorInputFrames: priorInputFrames)
    if !transitionGate.isActive {
      guard isForeignAutonomousTransitionEligible && !dragTracker.hasActiveSession else {
        return false
      }
      return beginAutonomousTransitionIfNeeded(observation, at: now)
    }
    return evaluateActiveAutonomousTransition(observation, at: now)
  }

  private func transitionObservation(
    resolvedWindowID: CGWindowID?, resolvedFrame: CGRect?, priorInputFrames: [Int: CGRect]
  ) -> WindowTransitionObservation {
    WindowTransitionObservation(
      current: .init(id: windowID, frame: windowFrame),
      resolved: .init(id: resolvedWindowID, frame: resolvedFrame),
      visibility: .init(
        currentFrames: inputWindowFrames, priorFrames: priorInputFrames,
        verifiedStandardFrames: roleSnapshot?.hasVerifiedWindowList == true
          ? roleSnapshot?.standardWindowFrames : nil))
  }

  private func beginAutonomousTransitionIfNeeded(
    _ observation: WindowTransitionObservation, at now: Double
  ) -> Bool {
    guard let initiation = observation.initiation else { return false }
    beginAutonomousTransition(
      originWindowID: initiation.originWindowID, reason: initiation.reason, at: now)
    if let candidate = initiation.candidate {
      transitionGate.observeCandidate(windowID: candidate.id, frame: candidate.frame, at: now)
    }
    return true
  }

  private func evaluateActiveAutonomousTransition(
    _ observation: WindowTransitionObservation, at now: Double
  ) -> Bool {
    let hold = WindowTransitionEvaluation.shouldHold(
      &transitionGate, observation: observation, at: now)
    if hold { scheduleTransitionPoll() } else { cancelAutonomousTransition() }
    return hold
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
      let native = NSApp.window(withWindowNumber: Int(id))
    {
      guard native.isVisible, !native.isMiniaturized,
        !minimizingNativeWindowIDs.contains(native.windowNumber)
      else { return (nil, nil) }
      resolvedWindowID = id
      next = native.frame
    }
    return (resolvedWindowID, next)
  }

  private func publishGeometry(
    _ next: CGRect?,
    windowID nextID: CGWindowID?,
    windowLayer nextLayer: Int = WindowServerSource.normalWindowLayer,
    publication: GeometryPublication = .manipulation
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
    if publication == .manipulation, let old, let next, previousID == nextID {
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
        schedule.once(.settle, after: Self.settleDelaySeconds) { [weak self] in self?.settle() }
      }
    } else if publication == .manipulation, currentManipulation != nil {
      schedule.cancel(.settle)
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
    guard started, observation.processID == processID, isEnabled, tracksWindows, !isSuspended else {
      return
    }
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
      schedule.cancel(.settle)
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
        beginAutonomousTransition(originWindowID: windowID, reason: .minimize, at: now)
      } else if observation.reason == kAXWindowDeminiaturizedNotification {
        beginAutonomousTransition(originWindowID: windowID, reason: .geometry, at: now)
      } else if isGeometryNotification
        && isForeignAutonomousTransitionEligible
        && !dragTracker.hasActiveSession
        && (windowID != nil || transitionGate.isActive)
      {
        beginAutonomousTransition(originWindowID: windowID, reason: .geometry, at: now)
      }
    }
    if !(isGeometryNotification && dragTracker.isPointerConfirmed) {
      refreshGeometry(scope: discover ? .applicationWindows : .trackedWindow)
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
    schedule.cancel(.settle)
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
      refreshGeometry(scope: .trackedWindow)
      return
    }
    clickSelection.record(at: eventPoint ?? CGPoint(x: point.x, y: top - point.y), now: now)
    refreshGeometry(scope: dragTracker.hasActiveSession ? .trackedWindow : .applicationWindows)
    scheduleFollowUpDiscovery()
  }

  private func handleMouseDragged(at now: Double) {
    guard tracksWindows else { return }
    isLeftMouseDown = true
    schedule.cancel(.settle)
    let handled = dragTracker.updateDrag(
      frame: windowFrame, hasWindow: windowID != nil, at: now, isLowPower: isLowPower)
    if handled && windowID != nil {
      clickSelection.clear()
      cancelFollowUpDiscovery()
    } else {
      refreshGeometry(
        scope: windowID == nil || clickSelection.point != nil ? .applicationWindows : .trackedWindow
      )
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
      refreshGeometry(scope: .applicationWindows)
      scheduleFollowUpDiscovery()
    } else {
      accessibilitySource?.refresh(reason: AccessibilityWindowSource.sampleReason)
      refreshGeometry(scope: windowID == nil ? .applicationWindows : .trackedWindow)
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
    schedule.cancel(.settle)
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
    let generation = observationGeneration
    let checkAccessibility = usesAccessibility
    Self.housekeepingQueue.async { [weak self] in
      let trusted = checkAccessibility && AXIsProcessTrusted()
      let elapsed: Double? = CGEventType(rawValue: UInt32.max).map {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
      }
      Task { @MainActor [weak self] in
        guard let self, self.observationGeneration == generation else { return }
        self.housekeepingInFlight = false
        guard self.started, self.isEnabled, !self.isSuspended else { return }
        if trusted != self.hasAccessibility {
          self.hasAccessibility = trusted
          self.followFrontmostApplication(.reconcileCurrent)
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

  private func receiveNotification(_ event: WorkspaceNotifications.Event) {
    switch event {
    case .activated: followFrontmostApplication()
    case .visibilityChanged, .spaceChanged: applicationVisibilityChanged()
    case .suspended: suspend()
    case .resumed: resume()
    case .environmentChanged: environmentChanged()
    case .displaysChanged: displaysChanged()
    case .windowChanged(let notification): localWindowChanged(notification)
    }
  }

  private func applicationVisibilityChanged() {
    followFrontmostApplication()
    if hasAccessibility { accessibilitySource?.refresh() }
    refreshGeometry(scope: .applicationWindows)
    scheduleFollowUpDiscovery()
  }
  private func localWindowChanged(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.canBecomeMain,
      window.styleMask.contains(.titled), let id = window.windowServerID,
      !WindowTrackingExclusions.excludesSurface(
        id, ownerPID: ProcessInfo.processInfo.processIdentifier)
    else { return }
    if notification.name == NSWindow.willMiniaturizeNotification {
      minimizingNativeWindowIDs.insert(Int(id))
    } else if notification.name == NSWindow.didMiniaturizeNotification
      || notification.name == NSWindow.didDeminiaturizeNotification
      || notification.name == NSWindow.willCloseNotification
    {
      minimizingNativeWindowIDs.remove(Int(id))
    }
    guard started, isEnabled, tracksWindows, !isSuspended,
      processID == ProcessInfo.processInfo.processIdentifier
    else { return }
    if notification.name == NSWindow.willCloseNotification
      || notification.name == NSWindow.willMiniaturizeNotification
      || notification.name == NSWindow.didMiniaturizeNotification
    {
      if id == windowID {
        publishGeometry(nil, windowID: nil)
      }
      refreshGeometry(scope: .applicationWindows)
      scheduleFollowUpDiscovery()
      return
    }
    guard window.isVisible, !window.isMiniaturized,
      !minimizingNativeWindowIDs.contains(Int(id))
    else { return }
    guard window.isMainWindow || window.isKeyWindow || id == windowID
    else { return }
    if notification.name == NSWindow.didMoveNotification
      || notification.name == NSWindow.didResizeNotification
    {
      roleSnapshot?.hasExactStandardWindowFrames = false
    }
    publishGeometry(window.frame, windowID: id)
  }
  private func displaysChanged() {
    refreshGeometry(scope: .applicationWindows)
    onGeometryChanged?()
  }
  private func environmentChanged() {
    isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    onEnvironmentChanged?()
  }
  private func suspend() {
    isSuspended = true
    endDrag()
    configureTimers()
    onEnvironmentChanged?()
  }
  private func resume() {
    isSuspended = false
    followFrontmostApplication(.reconcileCurrent)
    configureTimers()
    onEnvironmentChanged?()
  }
}
