import AppKit
import Observation
import SilliesCore

/// Owns lifetimes and routes events; platform tracking, decisions, artwork, and clips stay separate.
@MainActor @Observable
final class CompanionController {
  private static let baseCompanionSeed: UInt64 = 17
  private static let dropReturnDuration: Double = 0.5
  private static let maxHopDuration: Double = 0.55
  private static let hopArcHeightRatio: Double = 0.22
  private static let minimumDeadlineInterval: Double = 0.08
  private static let standardMotionFPS = 60
  private static let lowPowerMotionFPS = 30
  private static let neighborCheckCooldown: Double = 2.0
  private static let radialDwellDelay: Double = 0.24
  private static let radialDwellTolerance: Double = 18
  private static let radialDismissDistance: Double = 148
  private static let minimumDragDistanceForWheel: Double = 14
  private static let windowDropInteriorInset: Double = 14

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
  @ObservationIgnored private let radialWheel = RadialWheelController()
  @ObservationIgnored private let windowHighlight = WindowDropHighlightController()
  private(set) var liveCount = 0
  private(set) var movingCount = 0
  private(set) var lastReaction = "Settling in"
  private(set) var perchLocation = PerchSurface.Edge.unavailable
  @ObservationIgnored private var companions: [CompanionInstance] = []
  @ObservationIgnored private var motionTimer: Timer?
  @ObservationIgnored private var deadlineTimer: Timer?
  @ObservationIgnored private var dragDwellTimer: Timer?
  @ObservationIgnored private var draggedCompanionID: String?
  @ObservationIgnored private var draggedTarget: WindowTargetCandidate?
  @ObservationIgnored private var radialLayout: RadialSkillMenuLayout?
  @ObservationIgnored private var hoveredSkill: CompanionSkillKind?
  @ObservationIgnored private var dwellAnchor = CGPoint.zero
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
    settings.onChange = { [weak self] in self?.reconcile() }
    tracker.onEvent = { [weak self] in self?.route($0) }
    tracker.onGeometryChanged = { [weak self] in self?.geometryChanged() }
    tracker.onEnvironmentChanged = { [weak self] in self?.reconcile() }
    tracker.onApplicationChanged = { [weak self] in self?.reconcile() }
    skills.onBindingChanged = { [weak self] companionID, state in
      guard let self, let pet = self.companions.first(where: { $0.definition.id == companionID })
      else { return }
      let previousWindowID = pet.bindingState.boundTarget?.windowID
      let previousFrame = pet.bindingState.boundTarget?.frame
      pet.bindingState = state
      if previousWindowID != state.boundTarget?.windowID
        || previousFrame != state.boundTarget?.frame
      {
        self.updateSurfaces(animated: true)
      }
      pet.refreshHUD()
      if self.interaction.isEnabled { self.interaction.refresh() }
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
    clearDragSkillTargeting(closeWheel: true)
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
      pet.hud.close()
      pet.presentation.close()
    }
    companions.removeAll()
    started = false
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
    if !shouldRun {
      clearDragSkillTargeting(closeWheel: false)
      skills.stopAll()
    }
    for pet in companions {
      if !shouldRun {
        pet.isPickedUp = false
        pet.isReturningFromDrop = false
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
    if activeProducers { tracker.refreshInputBackgrounds() }
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
      if reducedMotion {
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
      if draggedCompanionID == pet.definition.id {
        clearDragSkillTargeting(closeWheel: false)
      }
      skills.unbind(companionID: pet.definition.id)
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
      pet.pickupPosition = pet.position
      pet.isPickedUp = true
      pet.isReturningFromDrop = false
      self.clearDragSkillTargeting(closeWheel: false)
      self.draggedCompanionID = pet.definition.id
      self.dwellAnchor = NSEvent.mouseLocation
      pet.hud.hide()
      self.interactionCounts[.pickedUp, default: 0] += 1
      pet.tween = nil
      pet.isStrolling = false
      pet.strollReachesEdge = false
      pet.panel.orderFrontRegardless()
      pet.place(at: pet.position)
      self.react(pet, to: WorkspaceEvent(.pickedUp, at: self.now))
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    pet.view.onDrag = { [weak self, weak pet] delta in
      guard let self, let pet else { return }
      let destination = CGPoint(
        x: pet.pickupPosition.x + delta.x, y: pet.pickupPosition.y + delta.y)
      pet.place(at: destination)
      self.updateDragSkillTargeting(for: pet, at: NSEvent.mouseLocation)
    }
    pet.view.onDrop = { [weak self, weak pet] dragged in
      guard let self, let pet else { return }
      let dropPointer = NSEvent.mouseLocation
      let selectedSkill = self.hoveredSkill
      let radialWasOpen = self.radialLayout != nil
      let candidateTarget =
        self.draggedTarget
        ?? (dragged
          ? WindowTargetResolver.resolveTarget(
            at: dropPointer, excludingWindowNumbers: self.excludedWindowNumbers())
          : nil)
      self.clearDragSkillTargeting(closeWheel: false)
      pet.isPickedUp = false
      self.interactionCounts[dragged ? .dropped : .pet, default: 0] += 1
      self.react(pet, to: WorkspaceEvent(dragged ? .dropped : .pet, at: self.now))

      let dropPosition = pet.position
      var boundOnDrop = false
      if dragged, let target = candidateTarget {
        if let selectedSkill {
          boundOnDrop = true
          self.skills.startSkill(
            selectedSkill, for: pet.definition.id, companionName: pet.definition.name,
            target: target)
        } else if radialWasOpen
          || self.shouldBindOnDrop(pet: pet, target: target, pointer: dropPointer)
        {
          boundOnDrop = true
          self.skills.presentSelectionPrompt(
            for: pet.definition.id, companionName: pet.definition.name, target: target)
        }
      }

      if dragged, !boundOnDrop, let surface = pet.surface {
        let destination = surface.clamped(dropPosition)
        if self.reducedMotion {
          pet.isReturningFromDrop = false
          pet.place(at: destination)
        } else {
          pet.isReturningFromDrop = true
          pet.place(at: dropPosition)
          self.move(
            pet, to: destination, duration: Self.dropReturnDuration, arc: 0)
        }
      } else if dragged, !boundOnDrop {
        pet.isReturningFromDrop = false
        pet.place(at: dropPosition)
      }
      pet.refreshHUD()
      self.scheduleDeadline()
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
  }

  private func excludedWindowNumbers() -> Set<Int> {
    var excluded = Set(companions.map { $0.panel.windowNumber })
    if let wheelNumber = radialWheel.windowNumber {
      excluded.insert(wheelNumber)
    }
    if let highlightNumber = windowHighlight.windowNumber {
      excluded.insert(highlightNumber)
    }
    for pet in companions {
      if let hudNumber = pet.hud.windowNumber {
        excluded.insert(hudNumber)
      }
    }
    return excluded
  }

  private func currentFocusedWindowCandidate() -> WindowTargetCandidate? {
    guard let windowID = tracker.windowID, let frame = tracker.windowFrame else { return nil }
    let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    return WindowTargetCandidate(
      windowID: windowID, processID: pid, appName: tracker.applicationName,
      bundleIdentifier: tracker.bundleIdentifier, windowTitle: nil, frame: frame)
  }

  private func updateDragSkillTargeting(for pet: CompanionInstance, at pointer: CGPoint) {
    if let layout = radialLayout, let target = draggedTarget {
      let distance = hypot(pointer.x - layout.anchor.x, pointer.y - layout.anchor.y)
      if distance > Self.radialDismissDistance {
        radialLayout = nil
        hoveredSkill = nil
        radialWheel.hide()
        dwellAnchor = pointer
      } else {
        let skill = layout.selectedSkill(at: pointer)
        hoveredSkill = skill
        windowHighlight.show(target: target, hoveredSkill: skill)
        radialWheel.show(
          companionName: pet.definition.name, target: target, layout: layout,
          hoveredSkill: skill)
        return
      }
    }

    let target = WindowTargetResolver.resolveTarget(
      at: pointer, excludingWindowNumbers: excludedWindowNumbers())
    draggedTarget = target

    let dragDistance = hypot(
      pet.position.x - pet.pickupPosition.x, pet.position.y - pet.pickupPosition.y)
    guard let target, dragDistance >= Self.minimumDragDistanceForWheel else {
      dragDwellTimer?.invalidate()
      dragDwellTimer = nil
      windowHighlight.hide()
      return
    }

    if shouldBindOnDrop(pet: pet, target: target, pointer: pointer) {
      windowHighlight.show(target: target, hoveredSkill: nil)
    } else {
      windowHighlight.hide()
    }

    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.option) || modifiers.contains(.command) {
      openRadialWheel(for: pet, target: target, at: pointer)
      return
    }

    if hypot(pointer.x - dwellAnchor.x, pointer.y - dwellAnchor.y) > Self.radialDwellTolerance
      || dragDwellTimer == nil
    {
      dwellAnchor = pointer
      dragDwellTimer?.invalidate()
      let companionID = pet.definition.id
      let timer = Timer(timeInterval: Self.radialDwellDelay, repeats: false) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.handleDragDwellTimeout(for: companionID)
        }
      }
      timer.tolerance = 0.02
      RunLoop.main.add(timer, forMode: .common)
      dragDwellTimer = timer
    }
  }

  private func handleDragDwellTimeout(for companionID: String) {
    dragDwellTimer = nil
    guard draggedCompanionID == companionID,
      radialLayout == nil,
      let pet = companions.first(where: { $0.definition.id == companionID }),
      pet.isPickedUp
    else { return }
    let pointer = NSEvent.mouseLocation
    guard
      let target =
        WindowTargetResolver.resolveTarget(
          at: pointer, excludingWindowNumbers: excludedWindowNumbers())
        ?? draggedTarget
    else { return }
    draggedTarget = target
    openRadialWheel(for: pet, target: target, at: pointer)
  }

  private func openRadialWheel(
    for pet: CompanionInstance, target: WindowTargetCandidate, at pointer: CGPoint
  ) {
    dragDwellTimer?.invalidate()
    dragDwellTimer = nil
    let visibleFrame =
      NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let layout = RadialSkillMenuLayout(center: pointer, visibleFrame: visibleFrame)
    radialLayout = layout
    hoveredSkill = nil
    windowHighlight.show(target: target, hoveredSkill: nil)
    radialWheel.show(
      companionName: pet.definition.name, target: target, layout: layout, hoveredSkill: nil)
  }

  private func shouldBindOnDrop(
    pet: CompanionInstance, target: WindowTargetCandidate, pointer: CGPoint
  ) -> Bool {
    let interior = target.frame.insetBy(
      dx: Self.windowDropInteriorInset, dy: Self.windowDropInteriorInset)
    guard interior.contains(pointer) else { return false }
    if let currentWindow = tracker.windowFrame, pet.attachedWindowID == tracker.windowID {
      let currentInterior = currentWindow.insetBy(
        dx: Self.windowDropInteriorInset, dy: Self.windowDropInteriorInset)
      if currentInterior.contains(pointer) {
        return true
      }
      let currentPerchEnvelope = currentWindow.insetBy(
        dx: -settings.size, dy: -settings.size * 1.25)
      if currentPerchEnvelope.contains(pet.position) {
        return false
      }
    }
    return true
  }

  private func clearDragSkillTargeting(closeWheel: Bool) {
    dragDwellTimer?.invalidate()
    dragDwellTimer = nil
    draggedCompanionID = nil
    draggedTarget = nil
    radialLayout = nil
    hoveredSkill = nil
    if closeWheel {
      windowHighlight.close()
      radialWheel.close()
    } else {
      windowHighlight.hide()
      radialWheel.hide()
    }
  }

  private func geometryChanged() {
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
        pet.surface = nil
        pet.attachedWindowID = nil
      }
      deadlineTimer?.invalidate()
      deadlineTimer = nil
      return
    }
    for (index, pet) in companions.enumerated() {
      let boundTarget = pet.bindingState.boundTarget
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
      let fraction = pet.surface?.fraction(for: pet.position, fallback: fallback) ?? fallback
      let target = surface.point(at: fraction)
      let changed = pet.surface != surface
      let reattached = pet.attachedWindowID != petWindowID || pet.surface?.edge != surface.edge
      pet.surface = surface
      pet.attachedWindowID = petWindowID
      pet.view.resize(to: surface.presentationSize)
      pet.view.configureSurface(
        pose: surface.attachmentPose, window: petWindow, display: screen.visibleFrame)
      guard surface.isAvailable || pet.isPickedUp else {
        pet.isReturningFromDrop = false
        pet.presentation.hide(immediately: true)
        pet.hud.hide()
        pet.tween = nil
        pet.isStrolling = false
        pet.strollReachesEdge = false
        continue
      }
      if shouldRun && !pet.isPickedUp {
        if changed || reattached {
          pet.isReturningFromDrop = false
          pet.place(at: target)
        } else {
          pet.view.updateWorldMask()
        }
        pet.presentation.show(
          reattached: reattached, reducedMotion: reducedMotion || tracker.isLowPower)
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
    for pet in companions where !pet.isPickedUp { react(pet, to: event) }
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
    playedAnimations[state.animation, default: 0] += 1
    animations.apply(
      state, to: pet.view.rig, characterID: pet.definition.id,
      reducedMotion: reducedMotion || tracker.isLowPower)
    if pet.isStrolling {
      pet.tween = nil
      pet.isStrolling = false
      pet.strollReachesEdge = false
    }
    guard !reducedMotion, !pet.isPickedUp, let surface = pet.surface, surface.isAvailable else {
      return
    }
    switch state.motion {
    case .none: break
    case .hop:
      let target = pet.tween?.end ?? surface.clamped(pet.position)
      move(
        pet, to: target, duration: min(state.expiresAt - now, Self.maxHopDuration),
        arc: settings.size * Self.hopArcHeightRatio)
    case .stroll:
      guard
        let plan = StrollPlan(
          from: pet.position, on: surface, speed: pet.definition.speed,
          activity: settings.activity.multiplier, maxDuration: state.expiresAt - now,
          random: &pet.random)
      else { return }
      pet.view.rig.setFacing(right: plan.facingRight)
      pet.tween = MotionTween(
        from: pet.position, to: plan.target, at: now, duration: plan.duration, linear: true)
      pet.isStrolling = true
      pet.strollReachesEdge = plan.reachesEdge
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
    where !pet.isPickedUp && (!settings.followsWindows || pet.surface?.isAvailable == true) {
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
        !$0.isPickedUp && (!settings.followsWindows || $0.surface?.isAvailable == true)
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
          pet.isReturningFromDrop = false
          pet.place(at: pet.position)
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
      }
    }
    if deadlineNeedsUpdate { scheduleDeadline() }
    updateMotionClock()
    if interaction.isEnabled { interaction.refresh() }
    if time >= nextNeighborCheck, companions.count > 1 {
      let nearby = NeighborProximity.nearbyIndices(
        positions: companions.map(\.position),
        edges: companions.map { $0.isPickedUp ? .unavailable : ($0.surface?.edge ?? .unavailable) },
        size: settings.size)
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
