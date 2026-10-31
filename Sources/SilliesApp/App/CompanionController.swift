import AppKit
import Observation
import SilliesCore

/// Owns lifetimes and routes events; platform tracking, decisions, artwork, and clips stay separate.
@MainActor @Observable
final class CompanionController {
  var activeSpeechModelID: String? { skills.activeAudioSession?.model.id }
  var activeDiarizationModelID: String? { skills.activeAudioSession?.diarizationModel?.id }
  private static let baseCompanionSeed: UInt64 = 17
  private static let maxHopDuration: Double = 0.55
  private static let hopArcHeightRatio: Double = 0.22
  private static let neighborCheckCooldown: Double = 2.0

  let settings: AppSettings
  let tracker: WorkspaceTracker
  let catalog: CharacterCatalog
  let renderers: RendererRegistry
  let animations: AnimationLibrary
  let transitions: TransitionLibrary
  let skills: SkillCoordinator
  let playfulScenes: PlayfulSceneCoordinator
  @ObservationIgnored private(set) lazy var commands = CommandDispatcher(
    skills: skills,
    environment: .init(
      isAvailable: { [weak self] in self?.shouldRun == true },
      companion: { [weak self] in self?.commandCompanion() },
      openVault: { [weak self] in self?.onOpenVault?(nil) },
      togglePause: { [weak self] in self?.settings.paused.toggle() },
      saveClipboard: { [weak self] id in
        guard let self, let pet = self.companions.first(where: { $0.definition.id == id }) else {
          return
        }
        self.skillControls.saveClipboard(with: pet)
      }))
  @ObservationIgnored var onOpenVault: ((UUID?) -> Void)?
  @ObservationIgnored var onWritingAnchorChanged: ((WritingCompanionAnchor?) -> Void)?
  @ObservationIgnored var onOpenWritingSession: (() -> Void)?
  @ObservationIgnored private let writingSelection = WritingCompanionSelection()
  private var writingCompanionID: String? { writingSelection.companionID }

  var hasAvailableWritingCompanion: Bool {
    writingSelection.isAvailable(in: companions)
  }

  @discardableResult func beginWritingIndicator() -> WritingCompanionAnchor? {
    playfulScenes.cancel(.restorePerches)
    guard let activation = writingSelection.begin(in: companions, at: now) else { return nil }
    if let state = activation.state { apply(state, to: activation.companion) }
    refreshPlayfulAvailability()
    scheduleDeadline()
    updateMotionClock()
    return activation.companion.writingAnchor
  }

  func endWritingIndicator() {
    writingSelection.end()
    refreshPlayfulAvailability()
    scheduleDeadline()
  }
  func finishWritingIndicator() {
    guard let activation = writingSelection.finish(), let state = activation.state else { return }
    activation.companion.displayBehavior(state, using: animations, reducedMotion: reducedMotion)
  }
  @ObservationIgnored private let additionalEventProducers: [any WorkspaceEventProducer]
  @ObservationIgnored private lazy var skillControls = CompanionSkillControls(
    skills: skills,
    environment: .init(
      isRunning: { [weak self] in self?.shouldRun == true },
      focusedTarget: { [weak self] in self?.currentFocusedWindowCandidate() },
      openVault: { [weak self] in self?.onOpenVault?($0) },
      openWritingSession: { [weak self] in self?.onOpenWritingSession?() },
      performSkill: { [weak self] skill, pet, target in
        self?.performSkillCommand(skill, for: pet, target: target)
      },
      motionChanged: { [weak self] in self?.updateMotionClock() }))
  @ObservationIgnored private let interaction = CompanionInteraction()
  @ObservationIgnored let dragTargeting: CompanionDragTargetingController
  @ObservationIgnored let smoothnessMetrics: InteractionSmoothnessMetrics
  private(set) var liveCount = 0
  private(set) var movingCount = 0
  private(set) var lastReaction = "Settling in"
  private(set) var perchLocation = PerchSurface.Edge.unavailable
  @ObservationIgnored private var companions: [CompanionInstance] = []
  @ObservationIgnored private let motionClock = CompanionMotionClock()
  @ObservationIgnored private let deadlineClock = CompanionDeadlineClock()
  @ObservationIgnored private var started = false
  @ObservationIgnored private var nextNeighborCheck: Double = 0
  @ObservationIgnored private(set) var playedAnimations: [AnimationID: Int] = [:]
  @ObservationIgnored private(set) var interactionCounts: [EventKind: Int] = [:]

  init(
    settings: AppSettings, assets: CompanionAssets = .init(), services: CompanionServices = .init()
  ) throws {
    let traceEnabled =
      ProcessInfo.processInfo.arguments.contains("--trace-drag")
      || ProcessInfo.processInfo.arguments.contains("--companion-drag-test")
    let metrics = DragResponseMetrics(enabled: traceEnabled)
    self.smoothnessMetrics = InteractionSmoothnessMetrics(enabled: traceEnabled)
    self.dragTargeting = CompanionDragTargetingController(metrics: metrics)
    self.settings = settings
    self.renderers = assets.renderers
    self.animations = assets.animations
    self.transitions = assets.transitions
    self.skills = services.skills
    self.additionalEventProducers = services.eventProducers
    tracker = WorkspaceTracker(accessibility: services.accessibility)
    let catalog = try assets.validatedCatalog()
    let scenes = try PlayfulSceneCatalog()
    try scenes.validate(characters: catalog, animations: assets.animations)
    self.catalog = catalog
    playfulScenes = PlayfulSceneCoordinator(
      catalog: scenes, animations: assets.animations,
      seed: UInt64.random(in: 1...UInt64.max))
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
        return "\(pet.definition.name) · \(skill.activeVerb) \(target?.appName ?? "Microphone")"
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
    connectCallbacks()
    dragTargeting.start()
    reconcile()
    tracker.start()
    for producer in additionalEventProducers { producer.start() }
  }

  private func connectCallbacks() {
    motionClock.onFrame = { [weak self] in self?.tick(at: $0) }
    deadlineClock.onDeadline = { [weak self] in self?.advanceBehaviors() }
    settings.onChange = { [weak self] in self?.reconcile() }
    connectDragTargeting()
    connectWorkspaceEvents()
    connectSkillEvents()
    for producer in additionalEventProducers {
      producer.onEvent = { [weak self] in self?.route($0) }
    }
  }

  private func connectDragTargeting() {
    dragTargeting.companionLookup = { [weak self] id in
      self?.companions.first(where: { $0.definition.id == id })
    }
    dragTargeting.excludedOverlayWindowNumbers = { [weak self] in
      self?.companionAndHUDWindowNumbers() ?? []
    }
    dragTargeting.currentTrackerWindowFrame = { [weak self] in self?.tracker.windowFrame }
    dragTargeting.currentCharacterSize = { [weak self] in self?.settings.size ?? 64 }
  }

  private func connectWorkspaceEvents() {
    tracker.onEvent = { [weak self] in self?.route($0) }
    tracker.onGeometryChanged = { [weak self] in self?.geometryChanged() }
    tracker.onEnvironmentChanged = { [weak self] in self?.reconcile() }
    tracker.onApplicationChanged = { [weak self] in self?.applicationChanged() }
  }

  private func connectSkillEvents() {
    skills.onBindingChanged = { [weak self] in self?.skillBindingChanged(for: $0, state: $1) }
    skills.onEmitEvent = { [weak self] in self?.skillEvent($1, for: $0) }
    skills.onOpenVaultRecord = { [weak self] in self?.onOpenVault?($0) }
  }

  private func applicationChanged() {
    commands.cancelPending()
    dragTargeting.refreshWindowSnapshot()
    skills.refreshBoundWindows()
    reconcile()
  }

  private func skillBindingChanged(for companionID: String, state: CompanionBindingState) {
    playfulScenes.cancel(.restorePerches)
    guard let pet = companions.first(where: { $0.definition.id == companionID }) else { return }
    let previousTarget = pet.attachmentTarget
    let wasVisible = pet.isAttachmentVisible
    pet.updateBinding(state)
    pet.updateSkillPresentation(skills.presentation(for: companionID))
    let targetChanged = previousTarget != pet.attachmentTarget
    if targetChanged {
      updateSurfaces(mode: .animated)
      if !wasVisible, pet.isAttachmentVisible {
        pet.displayBehavior(
          pet.behaviorState, using: animations, reducedMotion: reducedMotion || tracker.isLowPower)
      }
      scheduleDeadline()
      updateMotionClock()
    }
    pet.refreshHUD()
    if targetChanged, interaction.isEnabled { interaction.refresh() }
    refreshPlayfulAvailability()
    scheduleDeadline()
  }

  private func skillEvent(_ event: WorkspaceEvent, for companionID: String) {
    guard let pet = companions.first(where: { $0.definition.id == companionID }) else { return }
    if case .active(_, let skill, _, _, _) = pet.bindingState, skill.isAudioSession,
      event.kind == skill.eventKind, let state = pet.beginSustainedReaction(event)
    {
      apply(state, to: pet)
    } else {
      react(pet, to: event)
    }
    scheduleDeadline()
    updateMotionClock()
  }

  func stop() {
    commands.stop()
    writingSelection.end()
    playfulScenes.stop()
    dragTargeting.stop()
    dragTargeting.companionLookup = nil
    dragTargeting.excludedOverlayWindowNumbers = nil
    dragTargeting.currentTrackerWindowFrame = nil
    dragTargeting.currentCharacterSize = nil
    ApplicationIconCache.shared.cancelPending()
    skills.onBindingChanged = nil
    skills.onEmitEvent = nil
    skills.onOpenVaultRecord = nil
    skillControls.stop()
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
    deadlineClock.onDeadline = nil
    deadlineClock.cancel()
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
        $0.attachmentPose,
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
    companions.reduce(0) { $0 + $1.feedbackAnimationCount }
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
      decisionClockRunning: deadlineClock.isScheduled,
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

  private func refreshPlayfulAvailability() {
    let available =
      shouldRun && settings.activity == .playful && !companions.isEmpty
      && skills.activeAudioSession == nil && writingCompanionID == nil
      && !tracker.isManipulatingWindow
    playfulScenes.configure(
      available ? (reducedMotion || tracker.isLowPower ? .reducedMotion : .animated) : .suspended,
      at: now)
  }

  private func playfulOpportunity(trigger: PlayfulSceneDefinition.Trigger)
    -> PlayfulSceneDirector.Opportunity
  {
    let available = companions.compactMap { pet -> PlayfulSceneParticipant? in
      guard let profile = pet.definition.playful, let surface = pet.surface,
        pet.panel.isVisible, pet.isAttachmentVisible, !pet.isPickedUp, !pet.isReturningFromDrop,
        !pet.isWaitingForSpace, !pet.isStashTargeted, !pet.bindingState.isBound
      else { return nil }
      return PlayfulSceneParticipant(
        id: pet.definition.id, profile: profile, surface: surface,
        position: pet.position, windowID: pet.attachedWindowID)
    }
    let availableIDs = Set(available.map(\.id))
    let occupiedFrames = companions.filter {
      $0.panel.isVisible && !availableIDs.contains($0.definition.id)
    }.map { $0.panel.frame }
    return .init(
      time: now, trigger: trigger, participants: available,
      window: settings.followsWindows ? tracker.windowFrame : nil,
      visibleFrame: CompanionPanel.visibleFrame(for: companions.first?.panel.screen),
      occupiedFrames: occupiedFrames)
  }

  private func considerPlayfulScene(trigger: PlayfulSceneDefinition.Trigger) {
    guard !playfulScenes.isActive, let deadline = playfulScenes.nextDeadline, now >= deadline else {
      return
    }
    playfulScenes.consider(playfulOpportunity(trigger: trigger), companions: companions)
  }

  @discardableResult
  func previewPlayfulScene(_ id: String) -> Bool {
    refreshPlayfulAvailability()
    let started = playfulScenes.preview(
      id, opportunity: playfulOpportunity(trigger: .ambient), companions: companions)
    scheduleDeadline()
    updateMotionClock()
    return started
  }

  private func reconcile() {
    playfulScenes.cancel(.geometryChanging)
    reconcileEnabledCharacters()
    refreshPlayfulAvailability()
    if !shouldRun || companions.isEmpty {
      commands.stop()
      dragTargeting.resetAndHideOverlays()
      ApplicationIconCache.shared.cancelPending()
      skillControls.stop()
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
      skillControls.start()
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
      deadlineClock.cancel()
      if perchLocation != .unavailable { perchLocation = .unavailable }
      updateMotionClock()
      return
    }
    updateSurfaces(mode: .immediate)
    for pet in companions {
      guard !pet.isWaitingForSpace else {
        pet.resetPose()
        continue
      }
      if reducedMotion {
        if pet.isReturningFromDrop { pet.dropReturn.finish(for: pet, reducedMotion: true) }
        if let target = pet.tween?.end { pet.place(at: target) }
        pet.clearMotion()
      }
      pet.displayBehavior(
        pet.behaviorState, using: animations,
        reducedMotion: reducedMotion || tracker.isLowPower)
    }
    advanceBehaviors()
    updateMotionClock()
    if interaction.isEnabled {
      smoothnessMetrics.measureStage(.interaction) { interaction.refresh() }
    }
  }

  private func reconcileEnabledCharacters() {
    if let writingCompanionID, !settings.enabledCharacters.contains(writingCompanionID) {
      commands.stop()
    }
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
    skillControls.configure(pet)
    configureDragControls(pet)
  }

  private func configureDragControls(_ pet: CompanionInstance) {
    pet.configureDragControls(
      .init(
        pickup: { [weak self, weak pet] in
          guard let self, let pet else { return }
          self.pickUp(pet)
        },
        drag: { [weak self, weak pet] delta in
          guard let self, let pet else { return }
          self.drag(pet, by: delta)
        },
        release: { [weak self, weak pet] gesture in
          guard let self, let pet else { return }
          self.handleDrop(pet, gesture: gesture)
        }))
  }

  private func pickUp(_ pet: CompanionInstance) {
    if pet.isWritingIndicator { commands.onStopWriting?() }
    playfulScenes.cancel(.pickup(pet.definition.id))
    let target = currentFocusedWindowCandidate()
    pet.beginPickup(fallbackTarget: settings.followsWindows ? target : nil)
    dragTargeting.beginDrag(for: pet, seed: target, pointer: NSEvent.mouseLocation)
    interactionCounts[.pickedUp, default: 0] += 1
    react(pet, to: WorkspaceEvent(.pickedUp, at: now))
    updateMotionClock()
    if interaction.isEnabled {
      smoothnessMetrics.measureStage(.interaction) { interaction.refresh() }
    }
  }

  private func drag(_ pet: CompanionInstance, by delta: CGPoint) {
    smoothnessMetrics.measure(.companionDrag) {
      let destination = CGPoint(
        x: pet.pickupPosition.x + delta.x, y: pet.pickupPosition.y + delta.y)
      dragTargeting.metrics.measure(.movement) { pet.place(at: destination) }
      dragTargeting.metrics.measure(.targeting) {
        dragTargeting.updateDrag(for: pet, at: NSEvent.mouseLocation)
      }
    }
  }

  func startMicrophoneRecording() {
    commands.perform(.record)
  }

  private func commandCompanion() -> CommandDispatcher.Companion? {
    guard
      let pet = companions.filter({
        !$0.isPickedUp && !$0.bindingState.isBound && !$0.isWritingIndicator
      }).min(by: {
        hypot($0.position.x - NSEvent.mouseLocation.x, $0.position.y - NSEvent.mouseLocation.y)
          < hypot($1.position.x - NSEvent.mouseLocation.x, $1.position.y - NSEvent.mouseLocation.y)
      })
    else { return nil }
    return .init(id: pet.definition.id, name: pet.definition.name, position: pet.position)
  }

  private func performSkillCommand(
    _ skill: CompanionSkillKind, for pet: CompanionInstance, target: WindowTargetCandidate?
  ) {
    guard !pet.isWritingIndicator else { return }
    guard let command = AppCommand.allCases.first(where: { $0.skill == skill }) else { return }
    commands.perform(
      command,
      context: .init(
        companion: .init(id: pet.definition.id, name: pet.definition.name, position: pet.position),
        target: target))
  }

  private func handleDrop(_ pet: CompanionInstance, gesture: CompanionInstance.ReleaseGesture) {
    playfulScenes.cancel(.restorePerches)
    let selection = dragTargeting.finishDrag()
    let releasePosition = pet.position
    pet.endPickup()
    interactionCounts[gesture == .drag ? .dropped : .pet, default: 0] += 1
    guard gesture == .drag else {
      react(pet, to: WorkspaceEvent(.pet, at: now))
      scheduleDeadline()
      updateMotionClock()
      return
    }
    guard shouldRun, let surface = pet.surface, surface.isAvailable else {
      pet.dropReturn.cancel()
      updateSurfaces(mode: .immediate)
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
      self.considerPlayfulScene(trigger: .landing)
      if let selection {
        self.performSkillCommand(selection.skill, for: pet, target: selection.target)
      }
      self.scheduleDeadline()
      self.updateMotionClock()
      if self.interaction.isEnabled { self.interaction.refresh() }
    }
    scheduleDeadline()
    updateMotionClock()
    if interaction.isEnabled {
      smoothnessMetrics.measureStage(.interaction) { interaction.refresh() }
    }
  }

  private func companionAndHUDWindowNumbers() -> Set<Int> {
    companions.reduce(into: playfulScenes.windowNumbers) { $0.formUnion($1.overlayWindowNumbers) }
  }

  private func currentFocusedWindowCandidate() -> WindowTargetCandidate? {
    guard let windowID = tracker.windowID, let frame = tracker.windowFrame else { return nil }
    return WindowTargetCandidate(
      windowID: windowID, processID: tracker.processID, appName: tracker.applicationName,
      bundleIdentifier: tracker.bundleIdentifier, windowTitle: nil, frame: frame,
      windowLayer: tracker.windowLayer)
  }

  private func geometryChanged() {
    let path: InteractionSmoothnessMetrics.Path =
      if let latest = tracker.latestGeometry {
        latest.resized ? .windowResize : .windowMove
      } else {
        .windowSwitch
      }
    smoothnessMetrics.measure(path) {
      smoothnessMetrics.measureStage(.targeting) {
        dragTargeting.updateKnownWindow(tracker.windowID, frame: tracker.windowFrame)
        if tracker.latestGeometry == nil { skills.refreshBoundWindows() }
      }
      if !shouldRun {
        reconcile()
        return
      }
      smoothnessMetrics.measureStage(.surfaces) { updateSurfaces(mode: .animated) }
      smoothnessMetrics.measureStage(.behavior) {
        if !deadlineClock.isScheduled && !tracker.isManipulatingWindow { advanceBehaviors() }
      }
      smoothnessMetrics.measureStage(.clocks) { updateMotionClock() }
    }
  }

  private var surfacePlacement: CompanionSurfacePlacement {
    CompanionSurfacePlacement(
      companions: companions,
      environment: .init(
        window: tracker.windowFrame, windowID: tracker.windowID, windowLayer: tracker.windowLayer,
        followsWindows: settings.followsWindows,
        isAwaitingWindow: tracker.isAwaitingApplicationWindow,
        isRunning: shouldRun, reducedMotion: reducedMotion, isLowPower: tracker.isLowPower,
        characterSize: settings.size, geometryChange: tracker.latestGeometry),
      animations: animations, metrics: smoothnessMetrics)
  }

  private func updateSurfaces(mode: CompanionSurfacePlacement.Mode) {
    playfulScenes.cancel(.geometryChanging)
    var placement = surfacePlacement
    switch placement.update(mode: mode) {
    case .awaitingWindow: return
    case .unavailable:
      if writingCompanionID != nil { onWritingAnchorChanged?(nil) }
      deadlineClock.cancel()
      return
    case .positioned(let location):
      if perchLocation != location { perchLocation = location }
    }
    if writingCompanionID != nil { onWritingAnchorChanged?(writingSelection.anchor) }
    if interaction.isEnabled {
      smoothnessMetrics.measureStage(.interaction) { interaction.refresh() }
    }
  }

  private func route(_ event: WorkspaceEvent) {
    guard shouldRun else { return }
    if [.windowMoved, .windowResized, .appChanged, .windowDisappeared].contains(
      event.kind)
    {
      playfulScenes.cancel(.geometryChanging)
    }
    if event.kind == .userReturned { playfulScenes.cancel(.restorePerches) }
    if event.kind == .windowSettled {
      considerPlayfulScene(trigger: .windowSettled)
      for pet in companions {
        if reducedMotion { pet.resetWorkspaceFeedback() } else { pet.settleWorkspaceFeedback() }
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
    guard !pet.isPerformingScene, !pet.isWritingIndicator else { return }
    guard let state = pet.receive(event, activity: settings.activity.multiplier) else {
      return
    }
    apply(state, to: pet)
    lastReaction = "\(pet.definition.name) · \(state.animation.rawValue)"
  }

  private func apply(_ state: BehaviorState, to pet: CompanionInstance) {
    guard pet.isAttachmentVisible || pet.isPickedUp else { return }
    let hasActiveSurface =
      !settings.followsWindows
      || (pet.bindingState.isBound && pet.surface?.isAvailable == true)
      || (tracker.windowFrame != nil && tracker.windowID != nil && pet.surface?.isAvailable == true)
    guard hasActiveSurface else {
      pet.resetPose()
      return
    }
    if pet.isWaitingForSpace {
      settleAtFreePerch(pet, mode: .immediate)
      guard !pet.isWaitingForSpace else { return }
    }
    playedAnimations[state.animation, default: 0] += 1
    pet.displayBehavior(
      state, using: animations,
      reducedMotion: reducedMotion || tracker.isLowPower)
    if pet.isStrolling {
      pet.clearMotion()
    }
    guard !playfulScenes.isActive, !reducedMotion, !tracker.isManipulatingWindow, !pet.isPickedUp,
      !pet.isStashTargeted,
      !pet.isReturningFromDrop, let surface = pet.surface,
      surface.isAvailable
    else {
      return
    }
    switch state.motion {
    case .none:
      if pet.tween == nil { settleAtFreePerch(pet, mode: .animated) }
    case .hop:
      guard
        let target = PerchSpacing.nearestAvailablePoint(
          to: pet.tween?.end ?? surface.clamped(pet.position), on: surface,
          occupied: surfacePlacement.reservations(excluding: pet))
      else {
        settleAtFreePerch(pet, mode: .immediate)
        return
      }
      move(
        pet, to: target, duration: min(state.expiresAt - now, Self.maxHopDuration),
        arc: settings.size * Self.hopArcHeightRatio)
    case .stroll:
      guard
        let plan = pet.planStroll(
          activity: settings.activity.multiplier, until: state.expiresAt,
          reservations: surfacePlacement.reservations(excluding: pet), at: now)
      else {
        settleAtFreePerch(pet, mode: .animated)
        pet.displayBehavior(
          BehaviorState(), using: animations,
          reducedMotion: reducedMotion || tracker.isLowPower)
        return
      }
      pet.beginStroll(plan, at: now)
    }
  }

  private func settleAtFreePerch(_ pet: CompanionInstance, mode: CompanionSurfacePlacement.Mode) {
    var placement = surfacePlacement
    placement.settleAtFreePerch(pet, mode: mode)
  }

  private func move(_ pet: CompanionInstance, to target: CGPoint, duration: Double, arc: Double) {
    pet.move(to: target, duration: duration, arcHeight: arc, at: now)
  }

  private func advanceBehaviors() {
    guard shouldRun, !tracker.isManipulatingWindow else { return }
    let time = now
    refreshPlayfulAvailability()
    playfulScenes.advance(at: time)
    considerPlayfulScene(trigger: tracker.isIdle ? .idle : .ambient)
    for pet in companions
    where !pet.isPerformingScene && !pet.isWritingIndicator && !pet.isPickedUp
      && !pet.isReturningFromDrop
      && pet.isAttachmentVisible
      && (!settings.followsWindows || pet.surface?.isAvailable == true)
    {
      if let state = pet.advanceBehavior(
        at: time, activity: settings.activity.multiplier, isIdle: tracker.isIdle)
      {
        apply(state, to: pet)
      }
    }
    scheduleDeadline()
    updateMotionClock()
  }

  private func scheduleDeadline() {
    deadlineClock.cancel()
    guard shouldRun,
      let deadline =
        (companions.filter({
          !$0.isPerformingScene && !$0.isWritingIndicator && !$0.isPickedUp
            && !$0.isReturningFromDrop
            && $0.isAttachmentVisible
            && (!settings.followsWindows || $0.surface?.isAvailable == true)
        }).map(\.behaviorState.expiresAt) + [playfulScenes.nextDeadline].compactMap { $0 }).filter(
          \.isFinite
        ).min()
    else { return }
    deadlineClock.schedule(at: deadline)
  }

  private func updateMotionClock() {
    let count = shouldRun ? companions.filter { $0.tween != nil && !$0.isPickedUp }.count : 0
    if count != movingCount { movingCount = count }
    let pickedUp = companions.first(where: \.isPickedUp)
    guard shouldRun,
      let active = pickedUp ?? playfulScenes.motionCompanion
        ?? companions.first(where: { $0.tween != nil })
    else {
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
    let sceneWasActive = playfulScenes.isActive
    playfulScenes.advance(at: time)
    if sceneWasActive && !playfulScenes.isActive { scheduleDeadline() }
    for pet in companions where pet.isPickedUp {
      pet.view.continueDrag(at: NSEvent.mouseLocation)
    }
    var deadlineNeedsUpdate = false
    for pet in companions where !pet.isPerformingScene && !pet.isPickedUp {
      guard let arrival = pet.advanceMotion(at: time) else { continue }
      if pet.isReturningFromDrop {
        pet.dropReturn.finish(for: pet, reducedMotion: reducedMotion || tracker.isLowPower)
        deadlineNeedsUpdate = true
      }
      switch arrival {
      case .travel: break
      case .stroll, .edge:
        if arrival == .edge,
          let state = pet.receive(
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
      if pet.tween == nil { settleAtFreePerch(pet, mode: .animated) }
    }
    if deadlineNeedsUpdate { scheduleDeadline() }
    updateMotionClock()
    if interaction.isEnabled && !companions.contains(where: \.isPickedUp) {
      interaction.refresh()
    }
    if !playfulScenes.isActive, time >= nextNeighborCheck, companions.count > 1 {
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
