import AppKit
import QuartzCore
import SilliesCore

@MainActor
final class CompanionInstance {
  private static let motionSeedOffset: UInt64 = 41
  private static let layoutPlacementTolerance: CGFloat = 0.001
  private static let defaultPickupFraction = 0.5

  let definition: CharacterDefinition
  let view: CompanionView
  let panel: CompanionPanel
  let presentation: CompanionPresentation
  let hud = CompanionHUDController()
  let dropReturn = CompanionDropReturn()
  private let playback: BehaviorPlayback
  private var behavior: BehaviorEngine
  private var random: SeededRandom
  private(set) var position = CGPoint.zero
  private(set) var surface: PerchSurface?
  private(set) var tween: MotionTween?
  private(set) var isStrolling = false
  private(set) var strollReachesEdge = false
  private(set) var isStashTargeted = false
  private(set) var isPickedUp = false
  private(set) var isWaitingForSpace = false
  private(set) var isPerformingScene = false
  private(set) var isWritingIndicator = false

  func beginWritingIndicator(at time: TimeInterval) -> BehaviorState? {
    isWritingIndicator = true
    clearMotion()
    return behavior.beginSustainedReaction(WorkspaceEvent(.skillRecord, at: time))
  }

  func endWritingIndicator() {
    isWritingIndicator = false
    behavior.endSustainedReaction()
  }
  private(set) var needsPlacementAfterScene = false
  private var facingBeforeScene = true
  private var scenePickupFraction: Double?
  enum SceneReturn { case restorePerch, awaitGeometry, keepForPickup }

  func beginPlayfulScene() {
    isPerformingScene = true
    facingBeforeScene = view.rig.facingRight
    clearMotion()
    _ = view.rig.preparePlayfulProps()
  }

  func playSceneClip(
    _ frame: PlayfulSceneSession.Frame, library: AnimationLibrary,
    startingAt time: CFTimeInterval, reducedMotion: Bool
  ) {
    view.rig.preparePlayfulProps().configureScene(frame)
    if view.setScenePose(frame.pose) { needsPlacementAfterScene = true }
    library.apply(
      BehaviorState(animation: frame.animation), to: view.rig,
      characterID: definition.id, reducedMotion: reducedMotion)
    view.rig.articulatePlayfulPose()
    if !reducedMotion {
      PlayfulClipTiming.synchronize(view.rig.stage, startingAt: time)
      PlayfulClipTiming.synchronize(view.rig.hangingArms, startingAt: time)
    }
  }

  func placeInScene(_ frame: PlayfulSceneSession.Frame) {
    view.rig.setFacing(right: frame.facingRight)
    let edgeChanged = view.setSceneEdge(frame.edge)
    if edgeChanged {
      needsPlacementAfterScene = true
      CATransaction.begin()
      CATransaction.setDisableActions(true)
    }
    defer { if edgeChanged { CATransaction.commit() } }
    guard position != frame.position || needsPlacementAfterScene else { return }
    place(at: frame.position)
  }

  func endPlayfulScene(at home: CGPoint, placement: SceneReturn) {
    isPerformingScene = false
    view.setSceneEdge(nil)
    view.setScenePose(nil)
    view.rig.resetBehaviorPose()
    view.rig.setFacing(right: facingBeforeScene)
    switch placement {
    case .restorePerch: place(at: home)
    case .awaitGeometry:
      position = home
      needsPlacementAfterScene = true
    case .keepForPickup:
      scenePickupFraction = surface?.fraction(for: home)
    }
  }
  var isReturningFromDrop: Bool { dropReturn.isActive }
  var isUpright: Bool { view.rig.isUpright }
  var attachmentPose: AttachmentPose { view.rig.attachmentPose }
  var feedbackAnimationCount: Int { view.rig.feedbackAnimationCount }
  var overlayWindowNumbers: Set<Int> { hud.windowNumbers.union([panel.windowNumber]) }

  func resetPose() { view.rig.resetPose() }
  func settleWorkspaceFeedback() { view.rig.workspaceFeedback(lean: 0, stretch: 0, settling: true) }
  func configureSkillControls(_ controls: CompanionHUDModel.Controls) {
    hud.configureControls(controls)
  }
  func updateSkillPresentation(_ presentation: SkillPresentation) {
    hud.updatePresentation(presentation)
  }

  struct StashControls {
    let menu: () -> NSMenu
    let targetChanged: (Bool) -> Void
    let dropped: ([String]) -> Void
  }

  func configureStashControls(_ controls: StashControls) {
    view.onContextMenu = controls.menu
    view.onStashTargetChanged = controls.targetChanged
    view.onStashDropped = controls.dropped
  }

  enum ReleaseGesture { case click, drag }
  struct DragControls {
    let pickup: () -> Void
    let drag: (CGPoint) -> Void
    let release: (ReleaseGesture) -> Void
  }

  func configureDragControls(_ controls: DragControls) {
    view.onPickup = controls.pickup
    view.onDrag = controls.drag
    view.onDrop = { controls.release($0 ? .drag : .click) }
  }
  private(set) var pickupPosition = CGPoint.zero
  private(set) var pickupFraction = CompanionInstance.defaultPickupFraction
  private(set) var pickupWindowTarget: WindowTargetCandidate?
  private(set) var attachedWindowID: CGWindowID?
  private(set) var attachedWindowLayer: Int = WindowServerSource.normalWindowLayer
  private(set) var bindingState: CompanionBindingState = .followingFocusedWindow
  private var appliedLayoutSize: CGSize = .zero
  private(set) var placementCount = 0

  var attachmentTarget: WindowTargetCandidate? {
    return bindingState.boundTarget
  }
  var isAttachmentVisible: Bool { attachmentTarget?.isVisible ?? true }

  var attachmentSnapshot: PerchAttachmentChange.Previous {
    .init(
      surface: surface, windowID: attachedWindowID, position: position,
      heldFraction: isPickedUp || isReturningFromDrop ? pickupFraction : nil)
  }

  func configureSurface(_ surface: PerchSurface, window: CGRect?, display: CGRect) -> Bool {
    let previousPose = view.rig.attachmentPose
    view.resize(to: surface.presentationSize)
    view.configureSurface(pose: surface.attachmentPose, window: window, display: display)
    return previousPose != surface.attachmentPose
  }

  func refreshWorldMask() { view.updateWorldMask() }

  init(
    definition: CharacterDefinition, rig: CharacterRig, size: Double, seed: UInt64,
    transitions: TransitionLibrary
  ) {
    self.definition = definition
    if definition.playful != nil { _ = rig.preparePlayfulProps() }
    playback = BehaviorPlayback(rig: rig, characterID: definition.id)
    behavior = BehaviorEngine(character: definition, seed: seed)
    random = SeededRandom(seed: seed &+ Self.motionSeedOffset)
    view = CompanionView(rig: rig, size: size)
    view.setAccessibilityLabel(definition.name)
    panel = CompanionPanel(view: view)
    presentation = CompanionPresentation(
      panel: panel, view: view, profile: definition.presentationTransitions, library: transitions)
  }

  func updateBinding(_ state: CompanionBindingState) {
    bindingState = state
    updateOverlayLevel()
    panel.restoreAttachmentOrder()
    if !isAttachmentVisible, !isPickedUp { hideForUnavailableSurface() }
    if case .active(_, let skill, _, _, _) = state, skill.isAudioSession { return }
    behavior.endSustainedReaction()
  }

  func updateOverlayLevel() {
    presentation.updateAvailability(isPickedUp || isAttachmentVisible ? .available : .unavailable)
    if isPickedUp {
      panel.updateStacking(.pickedUp)
    } else if let target = attachmentTarget {
      panel.updateStacking(.bound(windowID: target.windowID, windowLayer: target.windowLayer))
    } else {
      panel.updateStacking(.following(windowLayer: attachedWindowLayer))
    }
  }

  func setStashTargeted(_ targeted: Bool) {
    isStashTargeted = targeted
    if targeted { clearMotion() }
  }

  func clearMotion() {
    tween = nil
    isStrolling = false
    strollReachesEdge = false
  }

  var behaviorState: BehaviorState { behavior.state }

  func receive(_ event: WorkspaceEvent, activity: Double) -> BehaviorState? {
    behavior.receive(event, activity: activity)
  }

  func beginSustainedReaction(_ event: WorkspaceEvent) -> BehaviorState? {
    behavior.beginSustainedReaction(event)
  }

  func advanceBehavior(at time: Double, activity: Double, isIdle: Bool) -> BehaviorState? {
    behavior.advance(
      at: time, activity: activity, isIdle: isIdle,
      ambientEvent: surface?.attachmentPose.isHanging == true ? .ambientWall : .ambient)
  }

  func planStroll(
    activity: Double, until deadline: Double, reservations: [PerchReservation], at time: Double
  ) -> StrollPlan? {
    guard let surface else { return nil }
    return StrollPlan(
      from: position, on: surface, speed: definition.speed, activity: activity,
      maxDuration: deadline - time, occupied: reservations, random: &random)
  }

  func displayBehavior(
    _ state: BehaviorState, using library: AnimationLibrary, reducedMotion: Bool
  ) {
    playback.apply(
      state, library: library, reducedMotion: reducedMotion)
  }

  func beginStroll(_ plan: StrollPlan, at time: Double) {
    view.rig.setFacing(right: plan.facingRight)
    tween = MotionTween(
      from: position, to: plan.target, at: time, duration: plan.duration, curve: .linear)
    isStrolling = true
    strollReachesEdge = plan.reachesEdge
  }

  func beginPickup(fallbackTarget: WindowTargetCandidate?) {
    pickupPosition = position
    pickupFraction =
      scenePickupFraction ?? surface?.fraction(for: position) ?? Self.defaultPickupFraction
    scenePickupFraction = nil
    pickupWindowTarget = attachmentTarget ?? fallbackTarget
    isPickedUp = true
    updateOverlayLevel()
    dropReturn.cancel()
    hud.hide()
    clearMotion()
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
    presentation.show(reducedMotion: true)
    place(at: position)
  }

  struct Attachment {
    let surface: PerchSurface
    let windowID: CGWindowID?
    let windowLayer: Int
  }

  enum MotionArrival { case travel, stroll, edge }

  func updateAttachment(_ attachment: Attachment) {
    surface = attachment.surface
    attachedWindowID = attachment.windowID
    attachedWindowLayer = attachment.windowLayer
    updateOverlayLevel()
  }

  func stagePlacement(at target: CGPoint) {
    dropReturn.cancel()
    position = target
  }

  func resumePerching(at target: CGPoint) {
    isWaitingForSpace = false
    place(at: target)
  }

  func endPickup() {
    isPickedUp = false
    updateOverlayLevel()
  }

  func beginMotion(_ motion: MotionTween) {
    clearMotion()
    tween = motion
  }

  func move(to target: CGPoint, duration: Double, arcHeight: Double, at time: Double) {
    if let tween { place(at: tween.position(at: time)) }
    beginMotion(
      MotionTween(
        from: position, to: target, at: time, duration: duration, arcHeight: arcHeight,
        arcDirection: surface?.outward ?? CGPoint(x: 0, y: 1)))
  }

  /// Samples movement on the shared clock and atomically completes its associated state.
  func advanceMotion(at time: Double) -> MotionArrival? {
    guard let tween else { return nil }
    place(at: tween.position(at: time))
    guard tween.isComplete(at: time) else { return nil }
    let arrival: MotionArrival =
      isStrolling
      ? (strollReachesEdge && surface?.isAtBoundary(position) == true ? .edge : .stroll) : .travel
    clearMotion()
    return arrival
  }

  func applyWorkspaceFeedback(_ feedback: WindowMotionFeedback) {
    view.rig.workspaceFeedback(lean: feedback.lean, stretch: feedback.stretch)
  }

  func resetWorkspaceFeedback() { view.rig.workspaceFeedback(lean: 0, stretch: 0) }

  func detachFromWindow(immediately: Bool) {
    presentation.hide(immediately: immediately)
    hud.hide()
    isWaitingForSpace = false
    clearMotion()
    dropReturn.cancel()
    surface = nil
    attachedWindowID = nil
    attachedWindowLayer = WindowServerSource.normalWindowLayer
  }

  func hideForUnavailableSurface() {
    dropReturn.cancel()
    presentation.hide(immediately: true)
    hud.hide()
    isWaitingForSpace = false
    clearMotion()
  }

  func waitForPerchSpace() {
    isWaitingForSpace = true
    clearMotion()
    hud.hide()
    presentation.hide(immediately: true)
  }

  func resetForInactiveSession() {
    view.cancelInteraction()
    isStashTargeted = false
    isPickedUp = false
    isWaitingForSpace = false
    dropReturn.cancel()
    bindingState = .followingFocusedWindow
    hud.hide()
    presentation.hide(immediately: true)
    clearMotion()
    view.rig.resetPose()
    behavior.reset()
  }

  func closeAllPanels() {
    view.cancelInteraction()
    dropReturn.cancel()
    hud.close()
    presentation.close()
  }

  func place(at point: CGPoint) {
    needsPlacementAfterScene = false
    placementCount += 1
    position = point
    updateOverlayLevel()
    let layout = view.panelLayout(at: point, attached: !isPickedUp && !isReturningFromDrop)
    let currentFrame = panel.frame
    let sizeChanged =
      abs(appliedLayoutSize.width - layout.frame.width) > Self.layoutPlacementTolerance
      || abs(appliedLayoutSize.height - layout.frame.height) > Self.layoutPlacementTolerance
    let originChanged =
      abs(currentFrame.minX - layout.frame.minX) > Self.layoutPlacementTolerance
      || abs(currentFrame.minY - layout.frame.minY) > Self.layoutPlacementTolerance
    if sizeChanged {
      appliedLayoutSize = layout.frame.size
      panel.setFrame(layout.frame, display: false)
    } else if originChanged {
      panel.setFrameOrigin(layout.frame.origin)
    }
    view.applyPanelLayout(layout)
    view.updateWorldMask()
    refreshHUD()
  }

  func refreshHUD() {
    guard bindingState.hasPresentation, isAttachmentVisible, panel.isVisible, !isPickedUp,
      !isReturningFromDrop,
      !isWaitingForSpace
    else {
      hud.hide()
      return
    }
    let visibleFrame = CompanionPanel.visibleFrame(for: panel.screen)
    hud.attachedWindowLayer = attachedWindowLayer
    hud.companionWindowNumber = panel.windowNumber
    hud.update(
      state: bindingState, companionPoint: position, characterSize: view.characterSize,
      visibleFrame: visibleFrame)
  }
}
