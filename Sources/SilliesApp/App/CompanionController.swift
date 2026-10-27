import AppKit
import Observation
import SilliesCore

/// Owns lifetimes and routes events; platform tracking, decisions, artwork, and clips stay separate.
@MainActor @Observable
final class CompanionController {
  private static let baseCompanionSeed: UInt64 = 17
  private static let maxHopDuration: Double = 0.55
  private static let hopArcHeightRatio: Double = 0.22
  private static let minimumDeadlineInterval: Double = 0.08
  private static let neighborCheckCooldown: Double = 2.0
  private static let minSettleDuration: Double = 0.12
  private static let maxSettleDuration: Double = 0.24
  private static let settleSpeedPointsPerSecond: Double = 360
  private static let positionChangeEpsilon: Double = 0.5
  private static let surfaceSpanChangeEpsilon: Double = 0.5

  @MainActor
  private struct SurfaceUpdateContext {
    let window: CGRect?
    let windowID: CGWindowID?
    let windowLayer: Int
    let screen: NSScreen?
    let animated: Bool
    private var visibleFrames: [ObjectIdentifier: CGRect] = [:]

    init(window: CGRect?, windowID: CGWindowID?, windowLayer: Int, animated: Bool) {
      self.window = window
      self.windowID = windowID
      self.windowLayer = windowLayer
      screen = CompanionController.preferredScreen(for: window)
      self.animated = animated
    }

    // NSScreen.visibleFrame can wait on WindowServer. Share one read per screen per pass,
    // but do not cache across passes: Dock/menu-bar changes alter the usable area.
    mutating func visibleFrame(for screen: NSScreen) -> CGRect {
      let key = ObjectIdentifier(screen)
      if let frame = visibleFrames[key] { return frame }
      let frame = CompanionPanel.visibleFrame(for: screen)
      visibleFrames[key] = frame
      return frame
    }
  }

  let settings: AppSettings
  let tracker: WorkspaceTracker
  let catalog: CharacterCatalog
  let renderers: RendererRegistry
  let animations: AnimationLibrary
  let transitions: TransitionLibrary
  let skills: SkillCoordinator
  @ObservationIgnored var onOpenVault: ((UUID?) -> Void)?
  @ObservationIgnored private let additionalEventProducers: [any WorkspaceEventProducer]
  @ObservationIgnored private let interaction = CompanionInteraction()
  @ObservationIgnored let dragTargeting: CompanionDragTargetingController
  @ObservationIgnored let smoothnessMetrics: InteractionSmoothnessMetrics
  private(set) var liveCount = 0
  private(set) var movingCount = 0
  private(set) var lastReaction = "Settling in"
  private(set) var perchLocation = PerchSurface.Edge.unavailable
  @ObservationIgnored private var companions: [CompanionInstance] = []
  @ObservationIgnored private var pendingPlacements: [ObjectIdentifier: Bool] = [:]
  @ObservationIgnored private let motionClock = CompanionMotionClock()
  @ObservationIgnored private var deadlineTimer: Timer?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var nextNeighborCheck: Double = 0
  @ObservationIgnored private(set) var playedAnimations: [AnimationID: Int] = [:]
  @ObservationIgnored private(set) var interactionCounts: [EventKind: Int] = [:]

  init(
    settings: AppSettings, useAccessibility: Bool = true,
    renderers: RendererRegistry = RendererRegistry(),
    animations: AnimationLibrary = AnimationLibrary(),
    transitions: TransitionLibrary = TransitionLibrary(),
    catalog: CharacterCatalog? = nil,
    skills: SkillCoordinator = SkillCoordinator(),
    eventProducers: [any WorkspaceEventProducer] = []
  ) throws {
    let traceEnabled =
      ProcessInfo.processInfo.arguments.contains("--trace-drag")
      || ProcessInfo.processInfo.arguments.contains("--companion-drag-test")
    let metrics = DragResponseMetrics(enabled: traceEnabled)
    self.smoothnessMetrics = InteractionSmoothnessMetrics(enabled: traceEnabled)
    self.dragTargeting = CompanionDragTargetingController(metrics: metrics)
    self.settings = settings
    self.renderers = renderers
    self.animations = animations
    self.transitions = transitions
    self.skills = skills
    self.additionalEventProducers = eventProducers
    tracker = WorkspaceTracker(useAccessibility: useAccessibility)
    self.catalog = try catalog ?? CharacterCatalog()
    try self.catalog.validateAssets(
      renderers: renderers, animations: animations, transitions: transitions)
  }

  var isExcluded: Bool {
    tracker.bundleIdentifier.map { settings.excludedApplications.contains($0) } ?? false
  }
  var shouldRun: Bool { !settings.paused && !tracker.isSuspended && !isExcluded }
  var reducedMotion: Bool {
    settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
  var restingDescription: String {
    if settings.paused { return "Taking a little break" }
    if isExcluded { return "Hidden in \(tracker.applicationName)" }
    if liveCount == 0 { return "Choose a little companion" }
    for pet in companions {
      if case .active(let target, let skill, _, _, _) = pet.bindingState {
        return "\(pet.definition.name) · \(skill.activeVerb) \(target.appName)"
      }
    }
    if !settings.followsWindows {
      return "Making your desktop a little happier"
    }
    if tracker.windowID == nil { return "Waiting for your next window" }
    if perchLocation == .unavailable {
      return "A little room around this window, please"
    }
    let onTop = perchLocation == .top
    return "\(onTop ? "Perched on" : "Clinging to") \(tracker.applicationName)"
  }

  func start() {
    guard !started else { return }
    started = true
    motionClock.onFrame = { [weak self] time in self?.tick(at: time) }
    dragTargeting.companionLookup = { [weak self] id in
      self?.companions.first(where: { $0.definition.id == id })
    }
    dragTargeting.excludedOverlayWindowNumbers = { [weak self] in
      self?.companionAndHUDWindowNumbers() ?? []
    }
    dragTargeting.currentTrackerWindowFrame = { [weak self] in
      self?.tracker.windowFrame
    }
    dragTargeting.currentCharacterSize = { [weak self] in
      self?.settings.size ?? 64
    }
    dragTargeting.start()
    settings.onChange = { [weak self] in self?.reconcile() }
    tracker.onEvent = { [weak self] in self?.route($0) }
    tracker.onGeometryChanged = { [weak self] in self?.geometryChanged() }
    tracker.onEnvironmentChanged = { [weak self] in self?.reconcile() }
    tracker.onApplicationChanged = { [weak self] in
      self?.dragTargeting.windowSnapshot.refresh()
      self?.reconcile()
    }
    skills.onBindingChanged = { [weak self] companionID, state in
      guard let self, let pet = self.companions.first(where: { $0.definition.id == companionID })
      else { return }
      let previousWindowID = pet.attachmentTarget?.windowID
      let previousFrame = pet.attachmentTarget?.frame
      pet.bindingState = state
      let targetChanged =
        previousWindowID != pet.attachmentTarget?.windowID
        || previousFrame != pet.attachmentTarget?.frame
      if targetChanged {
        self.updateSurfaces(animated: true)
      }
      pet.refreshHUD()
      if targetChanged, self.interaction.isEnabled { self.interaction.refresh() }
    }
    skills.onEmitEvent = { [weak self] companionID, event in
      guard let self, let pet = self.companions.first(where: { $0.definition.id == companionID })
      else { return }
      self.react(pet, to: event)
      self.scheduleDeadline()
      self.updateMotionClock()
    }
    skills.onOpenVaultRecord = { [weak self] recordID in
      self?.onOpenVault?(recordID)
    }
    for producer in additionalEventProducers {
      producer.onEvent = { [weak self] in self?.route($0) }
    }
    reconcile()
    tracker.start()
    for producer in additionalEventProducers {
      producer.start()
    }
  }

  func stop() {
    dragTargeting.stop()
    dragTargeting.companionLookup = nil
    dragTargeting.excludedOverlayWindowNumbers = nil
    dragTargeting.currentTrackerWindowFrame = nil
    dragTargeting.currentCharacterSize = nil
    ApplicationIconCache.shared.cancelPending()
    skills.onBindingChanged = nil
    skills.onEmitEvent = nil
    skills.onOpenVaultRecord = nil
    skills.stopAll()
    interaction.stop()
    settings.onChange = nil
    tracker.onEvent = nil
    tracker.onGeometryChanged = nil
    tracker.onEnvironmentChanged = nil
    tracker.onApplicationChanged = nil
    tracker.stop()
    for producer in additionalEventProducers {
      producer.onEvent = nil
      producer.stop()
    }
    motionClock.stop()
    motionClock.onFrame = nil
    deadlineTimer?.invalidate()
    deadlineTimer = nil
    for pet in companions {
      pet.closeAllPanels()
    }
    companions.removeAll()
    started = false
  }

  func stopAndFlush() async {
    stop()
    await skills.shutdown()
  }

  func flushForTermination(completion: @escaping @Sendable () -> Void) {
    stop()
    skills.flushForTermination(completion: completion)
  }

  func drainPreviewsForTermination() {
    skills.drainPreviewsForTermination()
  }

  var savedRecordCount: Int { skills.savedRecordCount }

  func greet() { route(WorkspaceEvent(.pet, at: now)) }
  func playReaction(_ kind: EventKind) { route(WorkspaceEvent(kind, at: now)) }

  var attachmentDiagnostics:
    [(
      edge: PerchSurface.Edge, point: CGPoint, visible: Bool, pose: AttachmentPose, upright: Bool,
      frame: CGRect
    )]
  {
    companions.map {
      (
        $0.surface?.edge ?? .unavailable, $0.position, $0.panel.isVisible,
        $0.view.rig.attachmentPose,
        $0.isUpright, $0.panel.frame
      )
    }
  }

  var dragOverlayDiagnostics: (windowID: UInt32?, highlight: Bool, wheel: Bool) {
    dragTargeting.diagnostics
  }
  var dragTimingSummary: String { dragTargeting.metrics.summary }
  var totalPlacementCount: Int { companions.reduce(0) { $0 + $1.placementCount } }
  var rigFeedbackAnimationCount: Int {
    companions.reduce(0) { $0 + $1.view.rig.feedbackAnimationCount }
  }
  var interactionMonitorInstallations: Int { interaction.monitorInstallations }
  var primaryCompanionView: CompanionView? { companions.first?.view }

  func exportWindowScene(_ window: NSWindow, name: String) {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("build/previews/\(name).png")
    do {
      try WindowSceneExporter.export(
        window: window,
        companions: companions.filter { $0.panel.isVisible }.map { ($0.view, $0.panel.frame) },
        to: url)
    } catch { print("Scene export failed: \(error)") }
  }

  var diagnostics: CompanionDiagnostics {
    CompanionDiagnostics(
      companionCount: companions.count,
      visibleCount: companions.filter { $0.panel.isVisible }.count,
      visibleHUDCount: companions.filter { $0.hud.isVisible }.count,
      movementClockRunning: motionClock.isRunning,
      decisionClockRunning: deadlineTimer != nil,
      clickThrough: companions.allSatisfy { $0.panel.ignoresMouseEvents },
      nonactivating: companions.allSatisfy { !$0.panel.canBecomeKey && !$0.panel.canBecomeMain }
    )
  }

  func blockingCompanionCount(at point: CGPoint) -> Int {
    interaction.refresh(at: point)
    let receiver = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
    return companions.filter { $0.panel.windowNumber == receiver && !$0.panel.ignoresMouseEvents }
      .count
  }

  func interactiveArtworkCount(at point: CGPoint) -> Int {
    companions.filter { $0.view.containsInteractiveArtwork(at: point) }.count
  }

  func toggleCurrentApplicationExclusion() {
    guard let bundle = tracker.bundleIdentifier else { return }
    if settings.excludedApplications.contains(bundle) {
      settings.excludedApplications.remove(bundle)
    } else {
      settings.excludedApplications.insert(bundle)
    }
  }

  private var now: Double { ProcessInfo.processInfo.systemUptime }

  private func reconcile() {
    reconcileEnabledCharacters()
    if !shouldRun || companions.isEmpty {
      dragTargeting.resetAndHideOverlays()
      ApplicationIconCache.shared.cancelPending()
      skills.stopAll()
    }
    if !shouldRun {
      for pet in companions {
        pet.resetForInactiveSession()
      }
    }
    // Paused/excluded companions stop observing other applications as well as rendering.
    let activeProducers = shouldRun && !companions.isEmpty
    tracker.configure(enabled: activeProducers, tracksWindows: settings.followsWindows)
    for producer in additionalEventProducers {
      producer.configure(enabled: activeProducers, tracksWindows: settings.followsWindows)
    }
    if activeProducers {
      dragTargeting.prepareOverlays()
      tracker.refreshInputBackgrounds()
    }
    interaction.configure(
      enabled: activeProducers,
      targets: companions.map { pet in
        CompanionInteraction.Target(
          panel: pet.panel, view: pet.view,
          isDragging: { [weak pet] in pet?.isPickedUp == true },
          isReturning: { [weak pet] in pet?.isReturningFromDrop == true })
      })
    guard shouldRun else {
      deadlineTimer?.invalidate()
      deadlineTimer = nil
      if perchLocation != .unavailable { perchLocation = .unavailable }
      updateMotionClock()
      return
    }
    updateSurfaces(animated: false)
    for pet in companions {
      guard !pet.isWaitingForSpace else {
        pet.view.rig.resetPose()
        continue
      }
      if reducedMotion {
        if pet.isReturningFromDrop { pet.dropReturn.finish(for: pet, reducedMotion: true) }
        if let target = pet.tween?.end { pet.place(at: target) }
        pet.clearMotion()
      }
      pet.displayBehavior(
        pet.behavior.state, using: animations,
        reducedMotion: reducedMotion || tracker.isLowPower)
    }
    advanceBehaviors()
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
  }

  private func reconcileEnabledCharacters() {
    for pet in companions where !settings.enabledCharacters.contains(pet.definition.id) {
      if dragTargeting.draggedCompanionID == pet.definition.id {
        dragTargeting.resetAndHideOverlays()
      }
      skills.unbind(companionID: pet.definition.id)
      pet.closeAllPanels()
    }
    companions.removeAll { !settings.enabledCharacters.contains($0.definition.id) }
    for (index, definition) in catalog.characters.enumerated()
    where settings.enabledCharacters.contains(definition.id)
      && !companions.contains(where: { $0.definition.id == definition.id })
    {
      guard let rig = renderers.make(definition.renderer) else { continue }
      let pet = CompanionInstance(
        definition: definition, rig: rig, size: settings.size,
        seed: UInt64(index) &+ Self.baseCompanionSeed,
        transitions: transitions)
      configureCompanionInput(pet)
      companions.append(pet)
    }
    liveCount = companions.count
  }

  private func configureCompanionInput(_ pet: CompanionInstance) {
    pet.hud.model.onStopSkill = { [weak self, weak pet] in
      guard let self, let pet else { return }
      self.skills.stopSkill(for: pet.definition.id)
    }
    pet.hud.model.onUnbind = { [weak self, weak pet] in
      guard let self, let pet else { return }
      self.skills.unbind(companionID: pet.definition.id)
    }
    pet.hud.model.onOpenVault = { [weak self] recordID in
      self?.onOpenVault?(recordID)
    }
    pet.hud.model.onFocusWindow = { target in
      NSRunningApplication(processIdentifier: target.processID)?.activate()
    }
    pet.view.onStashDropped = { [weak self, weak pet] items in
      guard let self, let pet else { return }
      let target = pet.bindingState.boundTarget ?? self.currentFocusedWindowCandidate()
      self.skills.recordStash(
        items: items, for: pet.definition.id, companionName: pet.definition.name,
        currentTarget: target)
    }
    pet.view.onPickup = { [weak self, weak pet] in
      guard let self, let pet else { return }
      let fallbackTarget = self.settings.followsWindows ? self.currentFocusedWindowCandidate() : nil
      pet.beginPickup(fallbackTarget: fallbackTarget)
      self.dragTargeting.beginDrag(
        for: pet, seed: self.currentFocusedWindowCandidate(), pointer: NSEvent.mouseLocation)
      self.interactionCounts[.pickedUp, default: 0] += 1
      self.react(pet, to: WorkspaceEvent(.pickedUp, at: self.now))
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    pet.view.onDrag = { [weak self, weak pet] delta in
      guard let self, let pet else { return }
      self.smoothnessMetrics.measure(.companionDrag) {
        let destination = CGPoint(
          x: pet.pickupPosition.x + delta.x, y: pet.pickupPosition.y + delta.y)
        self.dragTargeting.metrics.measure(.movement) { pet.place(at: destination) }
        self.dragTargeting.metrics.measure(.targeting) {
          self.dragTargeting.updateDrag(for: pet, at: NSEvent.mouseLocation)
        }
      }
    }
    pet.view.onDrop = { [weak self, weak pet] dragged in
      guard let self, let pet else { return }
      self.handleDrop(pet, dragged: dragged)
    }
  }

  private func handleDrop(_ pet: CompanionInstance, dragged: Bool) {
    let selection = dragTargeting.finishDrag()
    let releasePosition = pet.position
    pet.isPickedUp = false
    pet.updateOverlayLevel()
    interactionCounts[dragged ? .dropped : .pet, default: 0] += 1
    guard dragged else {
      react(pet, to: WorkspaceEvent(.pet, at: now))
      scheduleDeadline()
      updateMotionClock()
      return
    }
    guard shouldRun, let surface = pet.surface, surface.isAvailable else {
      pet.dropReturn.cancel()
      updateSurfaces(animated: false)
      updateMotionClock()
      return
    }
    let plan = DropReturnPlan(
      releasedAt: releasePosition, pickedUpAt: pet.pickupPosition,
      destination: surface.point(at: pet.pickupFraction),
      intent: selection == nil ? .returnToPerch : .activateSkill)
    pet.dropReturn.begin(for: pet, plan: plan, reducedMotion: reducedMotion) {
      [weak self, weak pet] in
      guard let self, let pet, self.shouldRun else { return }
      self.react(pet, to: WorkspaceEvent(.dropped, at: self.now))
      if let selection {
        self.skills.startSkill(
          selection.skill, for: pet.definition.id, companionName: pet.definition.name,
          target: selection.target)
      }
      self.scheduleDeadline()
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    scheduleDeadline()
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
  }

  private func companionAndHUDWindowNumbers() -> Set<Int> {
    var excluded = Set(companions.map { $0.panel.windowNumber })
    for pet in companions {
      if let hudNumber = pet.hud.windowNumber {
        excluded.insert(hudNumber)
      }
    }
    return excluded
  }

  private func currentFocusedWindowCandidate() -> WindowTargetCandidate? {
    guard let windowID = tracker.windowID, let frame = tracker.windowFrame else { return nil }
    return WindowTargetCandidate(
      windowID: windowID, processID: tracker.processID, appName: tracker.applicationName,
      bundleIdentifier: tracker.bundleIdentifier, windowTitle: nil, frame: frame,
      windowLayer: tracker.windowLayer)
  }

  private static func preferredScreen(for frame: CGRect?) -> NSScreen? {
    frame.flatMap { rect in
      NSScreen.screens.max { lhs, rhs in
        let a = lhs.frame.intersection(rect)
        let b = rhs.frame.intersection(rect)
        return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
      }
    } ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func geometryChanged() {
    let path: InteractionSmoothnessMetrics.Path =
      if let latest = tracker.latestGeometry {
        latest.resized ? .windowResize : .windowMove
      } else {
        .windowSwitch
      }
    smoothnessMetrics.measure(path) {
      dragTargeting.windowSnapshot.updateKnownWindow(tracker.windowID, frame: tracker.windowFrame)
      dragTargeting.targets.updateKnownWindow(tracker.windowID, frame: tracker.windowFrame)
      if tracker.latestGeometry == nil {
        skills.refreshBoundWindows()
      }
      if !shouldRun {
        reconcile()
        return
      }
      updateSurfaces(animated: true)
      if deadlineTimer == nil && !tracker.isManipulatingWindow { advanceBehaviors() }
      updateMotionClock()
    }
  }

  private func updateSurfaces(animated: Bool) {
    let defaultWindow = settings.followsWindows ? tracker.windowFrame : nil
    let defaultWindowID = settings.followsWindows ? tracker.windowID : nil
    let defaultWindowLayer =
      settings.followsWindows ? tracker.windowLayer : WindowServerSource.normalWindowLayer
    let hasBoundCompanion = companions.contains { $0.bindingState.isBound }
    if settings.followsWindows && (defaultWindow == nil || defaultWindowID == nil)
      && !hasBoundCompanion
    {
      guard !tracker.isAwaitingApplicationWindow else { return }
      hideAllCompanionsWhenNoWindowTracked()
      return
    }
    pendingPlacements.removeAll(keepingCapacity: true)
    var context = SurfaceUpdateContext(
      window: defaultWindow, windowID: defaultWindowID, windowLayer: defaultWindowLayer,
      animated: animated)
    var needsSurfaceArrangement = !animated
    for (index, pet) in companions.enumerated() {
      if updateCompanionSurface(pet, at: index, context: &context) {
        needsSurfaceArrangement = true
      }
    }
    if needsSurfaceArrangement {
      arrangeRestingCompanionsOnSurfaces()
    }
    flushPendingPlacements()
    let location =
      companions.first { $0.surface?.isAvailable == true }?.surface?.edge ?? .unavailable
    if perchLocation != location { perchLocation = location }
    if interaction.isEnabled { interaction.refresh() }
  }

  private func hideAllCompanionsWhenNoWindowTracked() {
    pendingPlacements.removeAll(keepingCapacity: true)
    let immediately = reducedMotion || tracker.isLowPower
    for pet in companions {
      pet.detachFromWindow(immediately: immediately)
    }
    deadlineTimer?.invalidate()
    deadlineTimer = nil
  }

  private func resolveTargetWindow(
    for pet: CompanionInstance,
    defaultWindow: CGRect?,
    defaultWindowID: CGWindowID?,
    defaultLayer: Int
  ) -> (frame: CGRect?, windowID: CGWindowID?, layer: Int) {
    guard let boundTarget = pet.attachmentTarget else {
      return (defaultWindow, defaultWindowID, defaultLayer)
    }
    let matchesDefault = boundTarget.windowID == defaultWindowID
    let frame = matchesDefault ? (defaultWindow ?? boundTarget.frame) : boundTarget.frame
    let layer = matchesDefault ? defaultLayer : boundTarget.windowLayer
    return (frame, boundTarget.windowID, layer)
  }

  private func updateCompanionSurface(
    _ pet: CompanionInstance,
    at index: Int,
    context: inout SurfaceUpdateContext
  ) -> Bool {
    let targetWindow = resolveTargetWindow(
      for: pet,
      defaultWindow: context.window,
      defaultWindowID: context.windowID,
      defaultLayer: context.windowLayer)
    if settings.followsWindows && (targetWindow.frame == nil || targetWindow.windowID == nil) {
      if pet.attachmentTarget == nil && tracker.isAwaitingApplicationWindow {
        return false
      }
      pet.detachFromWindow(immediately: reducedMotion || tracker.isLowPower)
      return false
    }
    let screen =
      targetWindow.frame == context.window
      ? context.screen : Self.preferredScreen(for: targetWindow.frame)
    guard let screen else { return false }
    let visibleFrame = context.visibleFrame(for: screen)
    let surface = PerchSurface(
      window: targetWindow.frame, visibleFrame: visibleFrame, characterSize: settings.size,
      preferRight: index % 2 == 1)
    let previousSurface = pet.surface
    let fallback = Double(index + 1) / Double(companions.count + 1)
    let fraction =
      pet.isPickedUp || pet.isReturningFromDrop
      ? pet.pickupFraction
      : (previousSurface?.fraction(for: pet.position, fallback: fallback) ?? fallback)
    let target = surface.point(at: fraction)
    let changed = previousSurface != surface
    let reattached =
      pet.attachedWindowID != targetWindow.windowID || previousSurface?.edge != surface.edge
    let surfaceLengthChanged =
      abs((previousSurface?.spanLength ?? 0) - surface.spanLength) > Self.surfaceSpanChangeEpsilon
      || abs((previousSurface?.presentationSize ?? 0) - surface.presentationSize)
        > Self.surfaceSpanChangeEpsilon
    let requiresArrangement =
      reattached || surfaceLengthChanged || pet.tween != nil || pet.isWaitingForSpace

    pet.surface = surface
    pet.attachedWindowID = targetWindow.windowID
    pet.attachedWindowLayer = targetWindow.layer
    pet.updateOverlayLevel()
    pet.view.resize(to: surface.presentationSize)
    let previousPose = pet.view.rig.attachmentPose
    pet.view.configureSurface(
      pose: surface.attachmentPose, window: targetWindow.frame, display: visibleFrame)
    guard surface.isAvailable || pet.isPickedUp else {
      pet.hideForUnavailableSurface()
      return requiresArrangement
    }
    if shouldRun && !pet.isPickedUp {
      if pet.isReturningFromDrop && !changed && !reattached {
        pet.view.updateWorldMask()
        return requiresArrangement
      }
      if changed || reattached {
        pet.dropReturn.cancel()
        pet.position = target
        pendingPlacements[ObjectIdentifier(pet)] = reattached
      } else {
        pet.view.updateWorldMask()
        pet.refreshHUD()
        if !pet.isWaitingForSpace {
          pet.presentation.show(
            reattached: false, reducedMotion: reducedMotion || tracker.isLowPower)
        }
      }
    } else if pet.isPickedUp {
      pet.view.updateWorldMask()
    }
    if !pet.isPickedUp && (changed || reattached) {
      applySurfaceMotionFeedback(
        to: pet, surface: surface, reattached: reattached, animated: context.animated)
    }
    if shouldRun, previousPose != surface.attachmentPose, !pet.isPickedUp {
      pet.displayBehavior(
        pet.behavior.state, using: animations,
        reducedMotion: reducedMotion || tracker.isLowPower)
    }
    return requiresArrangement
  }

  private func applySurfaceMotionFeedback(
    to pet: CompanionInstance,
    surface: PerchSurface,
    reattached: Bool,
    animated: Bool
  ) {
    pet.clearMotion()
    if reattached {
      pet.view.rig.workspaceFeedback(lean: 0, stretch: 0)
    } else if animated, let change = tracker.latestGeometry, !reducedMotion {
      let feedback = WindowMotionFeedback(
        edge: surface.edge, horizontalSpeed: change.horizontalSpeed,
        verticalSpeed: change.verticalSpeed, widthSpeed: change.widthSpeed,
        resized: change.resized)
      pet.view.rig.workspaceFeedback(lean: feedback.lean, stretch: feedback.stretch)
    }
  }

  private func arrangeRestingCompanionsOnSurfaces() {
    var arrangedSurfaces: [PerchSurface] = []
    for pet in companions where pet.tween == nil {
      guard let surface = pet.surface, !arrangedSurfaces.contains(surface) else { continue }
      if settleRestingGroup(on: surface, animated: false) {
        arrangedSurfaces.append(surface)
      } else {
        settleAtFreePerch(pet, animated: false)
      }
    }
  }

  private func flushPendingPlacements() {
    guard !pendingPlacements.isEmpty else { return }
    for pet in companions {
      guard let reattached = pendingPlacements.removeValue(forKey: ObjectIdentifier(pet)) else {
        continue
      }
      pet.place(at: pet.position)
      if !pet.isWaitingForSpace {
        pet.presentation.show(
          reattached: reattached, reducedMotion: reducedMotion || tracker.isLowPower)
      }
    }
  }

  private func route(_ event: WorkspaceEvent) {
    guard shouldRun else { return }
    if event.kind == .windowSettled {
      for pet in companions {
        pet.view.rig.workspaceFeedback(lean: 0, stretch: 0, settling: !reducedMotion)
      }
    }
    for pet in companions where !pet.isPickedUp && !pet.isReturningFromDrop {
      react(pet, to: event)
    }
    if event.kind == .windowSettled {
      advanceBehaviors()
    } else {
      scheduleDeadline()
      updateMotionClock()
    }
  }

  private func react(_ pet: CompanionInstance, to event: WorkspaceEvent) {
    guard let state = pet.behavior.receive(event, activity: settings.activity.multiplier) else {
      return
    }
    apply(state, to: pet)
    lastReaction = "\(pet.definition.name) · \(state.animation.rawValue)"
  }

  private func apply(_ state: BehaviorState, to pet: CompanionInstance) {
    let hasActiveSurface =
      !settings.followsWindows
      || (pet.bindingState.isBound && pet.surface?.isAvailable == true)
      || (tracker.windowFrame != nil && tracker.windowID != nil && pet.surface?.isAvailable == true)
    guard hasActiveSurface else {
      pet.view.rig.resetPose()
      return
    }
    if pet.isWaitingForSpace {
      settleAtFreePerch(pet, animated: false)
      guard !pet.isWaitingForSpace else { return }
    }
    playedAnimations[state.animation, default: 0] += 1
    pet.displayBehavior(
      state, using: animations,
      reducedMotion: reducedMotion || tracker.isLowPower)
    if pet.isStrolling {
      pet.clearMotion()
    }
    guard !reducedMotion, !tracker.isManipulatingWindow, !pet.isPickedUp,
      !pet.isReturningFromDrop, let surface = pet.surface,
      surface.isAvailable
    else {
      return
    }
    switch state.motion {
    case .none:
      if pet.tween == nil { settleAtFreePerch(pet, animated: true) }
    case .hop:
      guard
        let target = PerchSpacing.nearestAvailablePoint(
          to: pet.tween?.end ?? surface.clamped(pet.position), on: surface,
          occupied: perchReservations(excluding: pet))
      else {
        settleAtFreePerch(pet, animated: false)
        return
      }
      move(
        pet, to: target, duration: min(state.expiresAt - now, Self.maxHopDuration),
        arc: settings.size * Self.hopArcHeightRatio)
    case .stroll:
      guard
        let plan = StrollPlan(
          from: pet.position, on: surface, speed: pet.definition.speed,
          activity: settings.activity.multiplier, maxDuration: state.expiresAt - now,
          occupied: perchReservations(excluding: pet),
          random: &pet.random)
      else {
        settleAtFreePerch(pet, animated: true)
        pet.displayBehavior(
          BehaviorState(), using: animations,
          reducedMotion: reducedMotion || tracker.isLowPower)
        return
      }
      pet.beginStroll(plan, at: now)
    }
  }

  private func perchReservations(excluding pet: CompanionInstance) -> [PerchReservation] {
    companions.compactMap { other in
      guard other !== pet, !other.isWaitingForSpace,
        let surface = other.surface, surface.isAvailable
      else { return nil }
      let point =
        other.isPickedUp || other.isReturningFromDrop
        ? surface.point(at: other.pickupFraction)
        : surface.clamped(other.tween?.end ?? other.position)
      return PerchReservation(point: point, surface: surface)
    }
  }

  private func settleAtFreePerch(_ pet: CompanionInstance, animated: Bool) {
    guard shouldRun, !pet.isPickedUp, !pet.isReturningFromDrop,
      let surface = pet.surface, surface.isAvailable
    else { return }
    guard
      let target = PerchSpacing.nearestAvailablePoint(
        to: surface.clamped(pet.position), on: surface,
        occupied: perchReservations(excluding: pet))
    else {
      if !settleRestingGroup(on: surface, animated: animated) { waitForPerchSpace(pet) }
      return
    }
    placeAtRestingTarget(pet, target: target, animated: animated)
  }

  private func settleRestingGroup(on surface: PerchSurface, animated: Bool) -> Bool {
    guard shouldRun, surface.isAvailable else { return false }
    let group = companions.filter { $0.surface == surface }
    guard group.count > 1,
      group.allSatisfy({ !$0.isPickedUp && !$0.isReturningFromDrop && $0.tween == nil })
    else { return false }
    let targets = PerchSpacing.restingPoints(near: group.map(\.position), on: surface)
    for (pet, target) in zip(group, targets) {
      if let target {
        placeAtRestingTarget(pet, target: target, animated: animated)
      } else {
        waitForPerchSpace(pet)
      }
    }
    return true
  }

  private func waitForPerchSpace(_ pet: CompanionInstance) {
    pendingPlacements.removeValue(forKey: ObjectIdentifier(pet))
    pet.waitForPerchSpace()
  }

  private func placeAtRestingTarget(
    _ pet: CompanionInstance, target: CGPoint, animated: Bool
  ) {
    let pendingReattach = pendingPlacements.removeValue(forKey: ObjectIdentifier(pet))
    if pet.isWaitingForSpace {
      pet.isWaitingForSpace = false
      pet.place(at: target)
      pet.presentation.show(
        reattached: pendingReattach ?? false,
        reducedMotion: reducedMotion || tracker.isLowPower)
      pet.refreshHUD()
    } else if pendingReattach != nil
      || hypot(target.x - pet.position.x, target.y - pet.position.y) > Self.positionChangeEpsilon
    {
      if animated, pendingReattach == nil, !reducedMotion, !tracker.isLowPower {
        let distance = hypot(target.x - pet.position.x, target.y - pet.position.y)
        let settleDuration = min(
          Self.maxSettleDuration,
          max(Self.minSettleDuration, distance / Self.settleSpeedPointsPerSecond))
        move(pet, to: target, duration: settleDuration, arc: 0)
      } else {
        pet.place(at: target)
      }
      if let reattached = pendingReattach, !pet.isWaitingForSpace {
        pet.presentation.show(
          reattached: reattached, reducedMotion: reducedMotion || tracker.isLowPower)
      }
    }
  }

  private func move(_ pet: CompanionInstance, to target: CGPoint, duration: Double, arc: Double) {
    let time = now
    if let tween = pet.tween { pet.place(at: tween.position(at: time)) }
    pet.tween = MotionTween(
      from: pet.position, to: target, at: time, duration: duration, arcHeight: arc,
      arcDirection: pet.surface?.outward ?? CGPoint(x: 0, y: 1))
    pet.isStrolling = false
    pet.strollReachesEdge = false
  }

  private func advanceBehaviors() {
    guard shouldRun, !tracker.isManipulatingWindow else { return }
    let time = now
    for pet in companions
    where !pet.isPickedUp && !pet.isReturningFromDrop
      && (!settings.followsWindows || pet.surface?.isAvailable == true)
    {
      if let state = pet.behavior.advance(
        at: time, activity: settings.activity.multiplier, isIdle: tracker.isIdle,
        ambientEvent: pet.surface?.attachmentPose.isHanging == true ? .ambientWall : .ambient)
      {
        apply(state, to: pet)
      }
    }
    scheduleDeadline()
    updateMotionClock()
  }

  private func scheduleDeadline() {
    deadlineTimer?.invalidate()
    deadlineTimer = nil
    guard shouldRun,
      let deadline = companions.filter({
        !$0.isPickedUp && !$0.isReturningFromDrop
          && (!settings.followsWindows || $0.surface?.isAvailable == true)
      }).map(\.behavior.state.expiresAt).min()
    else { return }
    let interval = max(Self.minimumDeadlineInterval, deadline - now)
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.advanceBehaviors() }
    }
    timer.tolerance = Self.minimumDeadlineInterval
    RunLoop.main.add(timer, forMode: .common)
    deadlineTimer = timer
  }

  private func updateMotionClock() {
    let count = shouldRun ? companions.filter { $0.tween != nil && !$0.isPickedUp }.count : 0
    if count != movingCount { movingCount = count }
    let pickedUp = companions.first(where: \.isPickedUp)
    guard shouldRun, let active = pickedUp ?? companions.first(where: { $0.tween != nil }) else {
      motionClock.stop()
      return
    }
    let cadence: CompanionMotionClock.Cadence =
      tracker.isLowPower
      ? (pickedUp == nil ? .lowPowerMotion : .lowPowerInteraction) : .display
    motionClock.configure(
      screen: active.panel.screen ?? NSScreen.main ?? NSScreen.screens.first, cadence: cadence)
  }

  private func tick(at time: Double) {
    for pet in companions where pet.isPickedUp {
      pet.view.continueDrag(at: NSEvent.mouseLocation)
    }
    var deadlineNeedsUpdate = false
    for pet in companions where !pet.isPickedUp {
      guard let tween = pet.tween else { continue }
      pet.place(at: tween.position(at: time))
      if tween.isComplete(at: time) {
        pet.tween = nil
        if pet.isReturningFromDrop {
          pet.dropReturn.finish(for: pet, reducedMotion: reducedMotion || tracker.isLowPower)
          deadlineNeedsUpdate = true
        }
        if pet.isStrolling {
          let reachedEdge =
            pet.strollReachesEdge && (pet.surface?.isAtBoundary(pet.position) == true)
          pet.isStrolling = false
          pet.strollReachesEdge = false
          if reachedEdge,
            let state = pet.behavior.receive(
              WorkspaceEvent(.edgeReached, at: time), activity: settings.activity.multiplier)
          {
            apply(state, to: pet)
            lastReaction = "\(pet.definition.name) · \(state.animation.rawValue)"
            deadlineNeedsUpdate = true
          } else {
            pet.displayBehavior(
              BehaviorState(), using: animations,
              reducedMotion: reducedMotion || tracker.isLowPower)
          }
        }
        if pet.tween == nil { settleAtFreePerch(pet, animated: true) }
      }
    }
    if deadlineNeedsUpdate { scheduleDeadline() }
    updateMotionClock()
    if interaction.isEnabled && !companions.contains(where: \.isPickedUp) {
      interaction.refresh()
    }
    if time >= nextNeighborCheck, companions.count > 1 {
      let nearby = NeighborProximity.nearbyIndices(
        positions: companions.map(\.position),
        edges: companions.map {
          ($0.isPickedUp || $0.isReturningFromDrop || $0.isWaitingForSpace)
            ? .unavailable : ($0.surface?.edge ?? .unavailable)
        },
        size: PerchSpacing.greetingDistance(for: settings.size))
      if !nearby.isEmpty {
        nextNeighborCheck = time + Self.neighborCheckCooldown
        for index in nearby {
          react(companions[index], to: WorkspaceEvent(.neighbor, at: time))
        }
        scheduleDeadline()
        updateMotionClock()
      }
    }
  }
}
