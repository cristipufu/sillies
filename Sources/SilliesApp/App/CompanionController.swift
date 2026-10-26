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
  private static let standardMotionFPS = 60
  private static let lowPowerMotionFPS = 30
  private static let neighborCheckCooldown: Double = 2.0

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
  @ObservationIgnored private let dragTargeting: CompanionDragTargetingController
  private(set) var liveCount = 0
  private(set) var movingCount = 0
  private(set) var lastReaction = "Settling in"
  private(set) var perchLocation = PerchSurface.Edge.unavailable
  @ObservationIgnored private var companions: [CompanionInstance] = []
  @ObservationIgnored private var motionTimer: Timer?
  @ObservationIgnored private var deadlineTimer: Timer?
  @ObservationIgnored private var motionFPS = 0
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
    let metrics = DragResponseMetrics(
      enabled:
        ProcessInfo.processInfo.arguments.contains("--trace-drag")
        || ProcessInfo.processInfo.arguments.contains("--companion-drag-test"))
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
      switch state {
      case .awaitingSelection: break
      default: pet.selectionPerchTarget = nil
      }
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
    motionTimer?.invalidate()
    motionTimer = nil
    deadlineTimer?.invalidate()
    deadlineTimer = nil
    for pet in companions {
      pet.cancelPendingDropTarget()
      pet.dropReturn.cancel()
      pet.hud.close()
      pet.presentation.close()
    }
    companions.removeAll()
    started = false
  }

  func stopAndFlush() async {
    stop()
    skills.vault.cancelPendingSummaries()
    await skills.vault.flush()
  }

  func greet() { route(WorkspaceEvent(.pet, at: now)) }
  func playReaction(_ kind: EventKind) { route(WorkspaceEvent(kind, at: now)) }

  var attachmentDiagnostics:
    [(
      edge: PerchSurface.Edge, point: CGPoint, visible: Bool, pose: AttachmentPose, upright: Bool,
      frame: CGRect
    )]
  {
    companions.map {
      let transform = $0.view.rig.root.transform
      return (
        $0.surface?.edge ?? .unavailable, $0.position, $0.panel.isVisible,
        $0.view.rig.attachmentPose,
        abs(transform.m12) < 0.0001 && abs(transform.m21) < 0.0001, $0.panel.frame
      )
    }
  }

  var dragOverlayDiagnostics: (windowID: UInt32?, highlight: Bool, wheel: Bool) {
    dragTargeting.diagnostics
  }
  var dragTimingSummary: String { dragTargeting.metrics.summary }

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
      movementClockRunning: motionTimer != nil,
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
      dragTargeting.clear(closeWheel: false)
      ApplicationIconCache.shared.cancelPending()
      skills.stopAll()
    }
    for pet in companions {
      if !shouldRun {
        pet.cancelPendingDropTarget()
        pet.isPickedUp = false
        pet.dropReturn.cancel()
        pet.bindingState = .followingFocusedWindow
        pet.hud.hide()
        pet.presentation.hide(immediately: true)
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
        pet.view.rig.resetPose()
        pet.behavior.reset()
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
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
      }
      animations.apply(
        pet.behavior.state, to: pet.view.rig, characterID: pet.definition.id,
        reducedMotion: reducedMotion || tracker.isLowPower)
    }
    advanceBehaviors()
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
  }

  private func reconcileEnabledCharacters() {
    for pet in companions where !settings.enabledCharacters.contains(pet.definition.id) {
      if dragTargeting.draggedCompanionID == pet.definition.id {
        dragTargeting.clear(closeWheel: false)
      }
      skills.unbind(companionID: pet.definition.id)
      pet.cancelPendingDropTarget()
      pet.dropReturn.cancel()
      pet.hud.close()
      pet.presentation.close()
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
    pet.hud.model.onSelectSkill = { [weak self, weak pet] skill in
      guard let self, let pet, let target = pet.bindingState.boundTarget else { return }
      self.skills.startSkill(
        skill, for: pet.definition.id, companionName: pet.definition.name, target: target)
    }
    pet.hud.model.onStopSkill = { [weak self, weak pet] in
      guard let self, let pet else { return }
      self.skills.stopSkill(for: pet.definition.id)
    }
    pet.hud.model.onUnbind = { [weak self, weak pet] in
      guard let self, let pet else { return }
      pet.cancelPendingDropTarget()
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
      pet.cancelPendingDropTarget()
      pet.pickupPosition = pet.position
      pet.pickupFraction = pet.surface?.fraction(for: pet.position) ?? 0.5
      pet.pickupWindowTarget =
        pet.attachmentTarget
        ?? (self.settings.followsWindows ? self.currentFocusedWindowCandidate() : nil)
      pet.isPickedUp = true
      pet.dropReturn.cancel()
      self.dragTargeting.beginDrag(
        for: pet, seed: self.currentFocusedWindowCandidate(), pointer: NSEvent.mouseLocation)
      pet.hud.hide()
      self.interactionCounts[.pickedUp, default: 0] += 1
      pet.tween = nil
      pet.isStrolling = false
      pet.strollReachesEdge = false
      pet.panel.orderFrontRegardless()
      pet.presentation.show(reducedMotion: true)
      pet.place(at: pet.position)
      self.react(pet, to: WorkspaceEvent(.pickedUp, at: self.now))
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    pet.view.onDrag = { [weak self, weak pet] delta in
      guard let self, let pet else { return }
      let destination = CGPoint(
        x: pet.pickupPosition.x + delta.x, y: pet.pickupPosition.y + delta.y)
      self.dragTargeting.metrics.measure(.movement) { pet.place(at: destination) }
      self.dragTargeting.metrics.measure(.targeting) {
        self.dragTargeting.updateDrag(for: pet, at: NSEvent.mouseLocation)
      }
    }
    pet.view.onDrop = { [weak self, weak pet] dragged in
      guard let self, let pet else { return }
      self.handleDrop(pet, dragged: dragged)
    }
  }

  private func handleDrop(_ pet: CompanionInstance, dragged: Bool) {
    let pointer = NSEvent.mouseLocation
    let evaluation = dragTargeting.evaluateDrop(dragged: dragged, at: pointer)
    let selectedSkill = evaluation.selectedSkill
    let radialWasOpen = evaluation.radialWasOpen
    let dropTarget = evaluation.pendingDrop
    let cachedTarget = evaluation.cachedTarget
    let fallbackTarget = pet.pickupWindowTarget
    let releasePosition = pet.position
    let offerSkills = radialWasOpen || releasePosition.y < pet.pickupPosition.y
    pet.isPickedUp = false
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
      return
    }
    let plan = DropReturnPlan(
      releasedAt: releasePosition, pickedUpAt: pet.pickupPosition,
      destination: surface.point(at: pet.pickupFraction), selectedSkill: selectedSkill != nil)
    pet.dropReturn.begin(for: pet, plan: plan, reducedMotion: reducedMotion) {
      [weak self, weak pet] in
      guard let self, let pet, self.shouldRun else { return }
      self.react(pet, to: WorkspaceEvent(.dropped, at: self.now))
      if let cachedTarget {
        self.applyDropBinding(
          pet, target: cachedTarget, selectedSkill: selectedSkill, offerSkills: offerSkills,
          pointer: pointer, releasePosition: releasePosition)
      } else {
        // Fast drops must not block input waiting for a WindowServer reply.
        let resolver = self.dragTargeting.targets
        pet.pendingDropTarget = Task { [weak self, weak pet] in
          let target: WindowTargetCandidate?
          if let dropTarget {
            target = await resolver.resolveDrop(dropTarget) ?? fallbackTarget
          } else {
            target = fallbackTarget
          }
          guard !Task.isCancelled, let self, let pet, self.shouldRun, !pet.isPickedUp else {
            return
          }
          pet.pendingDropTarget = nil
          self.applyDropBinding(
            pet, target: target, selectedSkill: selectedSkill, offerSkills: offerSkills,
            pointer: pointer, releasePosition: releasePosition)
          self.scheduleDeadline()
          self.updateMotionClock()
        }
      }
      self.scheduleDeadline()
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    scheduleDeadline()
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
  }

  private func applyDropBinding(
    _ pet: CompanionInstance, target: WindowTargetCandidate?, selectedSkill: CompanionSkillKind?,
    offerSkills: Bool, pointer: CGPoint, releasePosition: CGPoint
  ) {
    guard let target else { return }
    let currentAttachedFrame =
      pet.attachedWindowID == tracker.windowID ? tracker.windowFrame : nil
    if let selectedSkill {
      skills.startSkill(
        selectedSkill, for: pet.definition.id, companionName: pet.definition.name, target: target)
    } else if offerSkills
      || DropReturnPlan.shouldBindOnDrop(
        targetFrame: target.frame,
        currentAttachedWindowFrame: currentAttachedFrame,
        pointer: pointer,
        companionPoint: releasePosition,
        characterSize: settings.size)
    {
      pet.selectionPerchTarget = pet.pickupWindowTarget
      skills.presentSelectionPrompt(
        for: pet.definition.id, companionName: pet.definition.name, target: target)
    }
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
      bundleIdentifier: tracker.bundleIdentifier, windowTitle: nil, frame: frame)
  }

  private func geometryChanged() {
    dragTargeting.windowSnapshot.updateKnownWindow(tracker.windowID, frame: tracker.windowFrame)
    if !shouldRun {
      reconcile()
      return
    }
    updateSurfaces(animated: true)
    if interaction.isEnabled { interaction.refresh() }
    if deadlineTimer == nil { advanceBehaviors() }
    updateMotionClock()
  }

  private func updateSurfaces(animated: Bool) {
    let defaultWindow = settings.followsWindows ? tracker.windowFrame : nil
    let defaultWindowID = settings.followsWindows ? tracker.windowID : nil
    let hasBoundCompanion = companions.contains { $0.bindingState.isBound }
    if settings.followsWindows && (defaultWindow == nil || defaultWindowID == nil)
      && !hasBoundCompanion
    {
      for pet in companions {
        pet.presentation.hide(immediately: reducedMotion || tracker.isLowPower)
        pet.hud.hide()
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
        pet.dropReturn.cancel()
        pet.surface = nil
        pet.attachedWindowID = nil
      }
      deadlineTimer?.invalidate()
      deadlineTimer = nil
      return
    }
    for (index, pet) in companions.enumerated() {
      let boundTarget = pet.attachmentTarget
      let petWindow: CGRect?
      let petWindowID: CGWindowID?
      if let boundTarget {
        petWindow =
          boundTarget.windowID == defaultWindowID
          ? (defaultWindow ?? boundTarget.frame) : boundTarget.frame
        petWindowID = boundTarget.windowID
      } else {
        petWindow = defaultWindow
        petWindowID = defaultWindowID
      }
      if settings.followsWindows && (petWindow == nil || petWindowID == nil) {
        pet.presentation.hide(immediately: reducedMotion || tracker.isLowPower)
        pet.hud.hide()
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
        pet.dropReturn.cancel()
        pet.surface = nil
        pet.attachedWindowID = nil
        continue
      }
      let screen =
        petWindow.flatMap { frame in
          NSScreen.screens.max { lhs, rhs in
            let a = lhs.frame.intersection(frame)
            let b = rhs.frame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
          }
        } ?? NSScreen.main ?? NSScreen.screens.first
      guard let screen else { continue }
      let surface = PerchSurface(
        window: petWindow, visibleFrame: screen.visibleFrame, characterSize: settings.size,
        preferRight: index % 2 == 1)
      let fallback = Double(index + 1) / Double(companions.count + 1)
      let fraction =
        pet.isPickedUp || pet.isReturningFromDrop
        ? pet.pickupFraction
        : (pet.surface?.fraction(for: pet.position, fallback: fallback) ?? fallback)
      let target = surface.point(at: fraction)
      let changed = pet.surface != surface
      let reattached = pet.attachedWindowID != petWindowID || pet.surface?.edge != surface.edge
      pet.surface = surface
      pet.attachedWindowID = petWindowID
      pet.view.resize(to: surface.presentationSize)
      pet.view.configureSurface(
        pose: surface.attachmentPose, window: petWindow, display: screen.visibleFrame)
      guard surface.isAvailable || pet.isPickedUp else {
        pet.dropReturn.cancel()
        pet.presentation.hide(immediately: true)
        pet.hud.hide()
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
        continue
      }
      if shouldRun && !pet.isPickedUp {
        if pet.isReturningFromDrop && !changed && !reattached {
          pet.view.updateWorldMask()
          continue
        }
        if changed || reattached {
          pet.dropReturn.cancel()
          pet.place(at: target)
        } else {
          pet.view.updateWorldMask()
        }
        if !pet.isWaitingForSpace {
          pet.presentation.show(
            reattached: reattached, reducedMotion: reducedMotion || tracker.isLowPower)
        }
        pet.refreshHUD()
      } else if pet.isPickedUp {
        pet.view.updateWorldMask()
      }
      guard !pet.isPickedUp, changed || reattached else { continue }
      pet.tween = nil
      pet.isStrolling = false
      pet.strollReachesEdge = false
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
    var arrangedSurfaces: [PerchSurface] = []
    for pet in companions where pet.tween == nil {
      guard let surface = pet.surface, !arrangedSurfaces.contains(surface) else { continue }
      if settleRestingGroup(on: surface, animated: false) {
        arrangedSurfaces.append(surface)
      } else {
        settleAtFreePerch(pet, animated: false)
      }
    }
    let location =
      companions.first { $0.surface?.isAvailable == true }?.surface?.edge ?? .unavailable
    if perchLocation != location { perchLocation = location }
    if interaction.isEnabled { interaction.refresh() }
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
    scheduleDeadline()
    updateMotionClock()
  }

  private func react(_ pet: CompanionInstance, to event: WorkspaceEvent) {
    guard let state = pet.behavior.receive(event, activity: settings.activity.multiplier) else {
      return
    }
    apply(state, to: pet)
    lastReaction = "\(pet.definition.name) · \(state.animation.rawValue)"
  }

  private func apply(_ state: BehaviorState, to pet: CompanionInstance) {
    guard !settings.followsWindows || pet.surface?.isAvailable == true else {
      pet.view.rig.resetPose()
      return
    }
    if pet.isWaitingForSpace {
      settleAtFreePerch(pet, animated: false)
      guard !pet.isWaitingForSpace else { return }
    }
    playedAnimations[state.animation, default: 0] += 1
    animations.apply(
      state, to: pet.view.rig, characterID: pet.definition.id,
      reducedMotion: reducedMotion || tracker.isLowPower)
    if pet.isStrolling {
      pet.tween = nil
      pet.isStrolling = false
      pet.strollReachesEdge = false
    }
    guard !reducedMotion, !pet.isPickedUp, !pet.isReturningFromDrop, let surface = pet.surface,
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
        animations.apply(
          BehaviorState(), to: pet.view.rig, characterID: pet.definition.id,
          reducedMotion: reducedMotion || tracker.isLowPower)
        return
      }
      pet.view.rig.setFacing(right: plan.facingRight)
      pet.tween = MotionTween(
        from: pet.position, to: plan.target, at: now, duration: plan.duration, curve: .linear)
      pet.isStrolling = true
      pet.strollReachesEdge = plan.reachesEdge
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
    pet.isWaitingForSpace = true
    pet.tween = nil
    pet.isStrolling = false
    pet.strollReachesEdge = false
    pet.hud.hide()
    pet.presentation.hide(immediately: true)
  }

  private func placeAtRestingTarget(
    _ pet: CompanionInstance, target: CGPoint, animated: Bool
  ) {
    if pet.isWaitingForSpace {
      pet.isWaitingForSpace = false
      pet.place(at: target)
      pet.presentation.show(reducedMotion: reducedMotion || tracker.isLowPower)
      pet.refreshHUD()
    } else if hypot(target.x - pet.position.x, target.y - pet.position.y) > 0.5 {
      if animated, !reducedMotion, !tracker.isLowPower {
        let distance = hypot(target.x - pet.position.x, target.y - pet.position.y)
        move(pet, to: target, duration: min(0.24, max(0.12, distance / 360)), arc: 0)
      } else {
        pet.place(at: target)
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
    guard shouldRun else { return }
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
    guard movingCount > 0 else {
      motionTimer?.invalidate()
      motionTimer = nil
      motionFPS = 0
      return
    }
    let fps = tracker.isLowPower ? Self.lowPowerMotionFPS : Self.standardMotionFPS
    guard motionTimer == nil || motionFPS != fps else { return }
    motionTimer?.invalidate()
    motionFPS = fps
    let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = 0.002
    RunLoop.main.add(timer, forMode: .common)
    motionTimer = timer
  }

  private func tick() {
    let time = now
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
            animations.apply(
              BehaviorState(), to: pet.view.rig, characterID: pet.definition.id,
              reducedMotion: reducedMotion || tracker.isLowPower)
          }
        }
        if pet.tween == nil { settleAtFreePerch(pet, animated: true) }
      }
    }
    if deadlineNeedsUpdate { scheduleDeadline() }
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
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
