import AppKit
import ApplicationServices
import Observation
import QuartzCore
import SilliesCore

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
  private static let transitionPollInterval: Double = 0.09
  private nonisolated static let housekeepingQueue = DispatchQueue(
    label: "app.sillies.housekeeping", qos: .utility)

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
  @ObservationIgnored private let schedule = WindowTrackingSchedule()
  @ObservationIgnored private var throttle = EventThrottle()
  @ObservationIgnored private var isEnabled = true
  @ObservationIgnored private var tracksWindows = true
  @ObservationIgnored private var started = false
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
    updateMetadataWorkerActivity()
    geometrySource = WindowServerSource { [weak self] value in
      MainRunLoopDelivery.perform { [weak self] in self?.accept(value) }
    }
    accessibilitySource = AccessibilityWindowSource { [weak self] value in
      MainRunLoopDelivery.perform { [weak self] in self?.acceptAccessibility(value) }
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
    followFrontmostApplication(.reconcileCurrent)
    configureTimers()
  }

  func stop() {
    started = false
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
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
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

  private enum FocusRefresh { case applicationChanged, reconcileCurrent }

  private func followFrontmostApplication(_ refresh: FocusRefresh = .applicationChanged) {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    if refresh == .applicationChanged && processID == app.processIdentifier { return }
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      if NSApp.keyWindow is CompanionUtilityWindow { return }
      guard
        NSApp.windows.contains(where: {
          $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain && $0.styleMask.contains(.titled)
        })
      else { return }
    } else {
      guard TrackableApplicationPolicy.isTrackable(app) else { return }
    }
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
        refreshGeometry(scope: .applicationWindows)
      }
      scheduleFollowUpDiscovery()
    }
    onApplicationChanged?()
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
    if let id = observation.windowID, WindowTrackingExclusions.shared.contains(id) { return }
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
      publishGeometry(nil, windowID: nil, suppressManipulationEvent: true)
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
        schedule.once(.settle, after: Self.settleDelaySeconds) { [weak self] in self?.settle() }
      }
    } else if !suppressManipulationEvent, currentManipulation != nil {
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

  @objc private func activated() { followFrontmostApplication() }
  @objc private func applicationVisibilityChanged() {
    followFrontmostApplication()
    if hasAccessibility { accessibilitySource?.refresh() }
    refreshGeometry(scope: .applicationWindows)
    scheduleFollowUpDiscovery()
  }
  @objc private func localWindowChanged(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.canBecomeMain,
      window.styleMask.contains(.titled), window.windowNumber > 0
    else { return }
    if notification.name == NSWindow.willMiniaturizeNotification {
      minimizingNativeWindowIDs.insert(window.windowNumber)
    } else if notification.name == NSWindow.didMiniaturizeNotification
      || notification.name == NSWindow.didDeminiaturizeNotification
      || notification.name == NSWindow.willCloseNotification
    {
      minimizingNativeWindowIDs.remove(window.windowNumber)
    }
    guard started, isEnabled, tracksWindows, !isSuspended,
      processID == ProcessInfo.processInfo.processIdentifier
    else { return }
    if notification.name == NSWindow.willCloseNotification
      || notification.name == NSWindow.willMiniaturizeNotification
      || notification.name == NSWindow.didMiniaturizeNotification
    {
      if UInt32(window.windowNumber) == windowID {
        publishGeometry(nil, windowID: nil)
      }
      refreshGeometry(scope: .applicationWindows)
      scheduleFollowUpDiscovery()
      return
    }
    guard window.isVisible, !window.isMiniaturized,
      !minimizingNativeWindowIDs.contains(window.windowNumber)
    else { return }
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
    refreshGeometry(scope: .applicationWindows)
    scheduleFollowUpDiscovery()
  }
  @objc private func displaysChanged() {
    refreshGeometry(scope: .applicationWindows)
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
    followFrontmostApplication(.reconcileCurrent)
    configureTimers()
    onEnvironmentChanged?()
  }
}
