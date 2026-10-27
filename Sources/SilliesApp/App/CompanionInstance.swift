import AppKit
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
  var behavior: BehaviorEngine
  var random: SeededRandom
  var position = CGPoint.zero
  var surface: PerchSurface?
  var tween: MotionTween?
  var isStrolling = false
  var strollReachesEdge = false
  var isPickedUp = false
  var isWaitingForSpace = false
  var isReturningFromDrop: Bool { dropReturn.isActive }
  var isUpright: Bool { view.rig.isUpright }
  var pickupPosition = CGPoint.zero
  var pickupFraction = CompanionInstance.defaultPickupFraction
  var pickupWindowTarget: WindowTargetCandidate?
  var attachedWindowID: CGWindowID?
  var attachedWindowLayer: Int = WindowServerSource.normalWindowLayer
  var bindingState: CompanionBindingState = .followingFocusedWindow
  private var appliedLayoutSize: CGSize = .zero
  private(set) var placementCount = 0

  var attachmentTarget: WindowTargetCandidate? {
    return bindingState.boundTarget
  }

  init(
    definition: CharacterDefinition, rig: CharacterRig, size: Double, seed: UInt64,
    transitions: TransitionLibrary
  ) {
    self.definition = definition
    playback = BehaviorPlayback(rig: rig, characterID: definition.id)
    behavior = BehaviorEngine(character: definition, seed: seed)
    random = SeededRandom(seed: seed &+ Self.motionSeedOffset)
    view = CompanionView(rig: rig, size: size)
    view.setAccessibilityLabel(definition.name)
    panel = CompanionPanel(view: view)
    presentation = CompanionPresentation(
      panel: panel, view: view, profile: definition.presentationTransitions, library: transitions)
  }

  func updateOverlayLevel() {
    panel.updateOverlayLevel(forWindowLayer: attachedWindowLayer, isPickedUp: isPickedUp)
  }

  func clearMotion() {
    tween = nil
    isStrolling = false
    strollReachesEdge = false
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
    pickupFraction = surface?.fraction(for: position) ?? Self.defaultPickupFraction
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
    placementCount += 1
    position = point
    updateOverlayLevel()
    let layout = view.panelLayout(at: point, attached: !isPickedUp && !isReturningFromDrop)
    let sizeChanged =
      abs(appliedLayoutSize.width - layout.frame.width) > Self.layoutPlacementTolerance
      || abs(appliedLayoutSize.height - layout.frame.height) > Self.layoutPlacementTolerance
    if sizeChanged {
      appliedLayoutSize = layout.frame.size
      panel.setFrame(layout.frame, display: false)
    } else if abs(panel.frame.minX - layout.frame.minX) > Self.layoutPlacementTolerance
      || abs(panel.frame.minY - layout.frame.minY) > Self.layoutPlacementTolerance
    {
      panel.setFrameOrigin(layout.frame.origin)
    }
    view.applyPanelLayout(layout)
    view.updateWorldMask()
    refreshHUD()
  }

  func refreshHUD() {
    guard bindingState.isBound, panel.isVisible, !isPickedUp, !isReturningFromDrop,
      !isWaitingForSpace
    else {
      hud.hide()
      return
    }
    let visibleFrame = CompanionPanel.visibleFrame(for: panel.screen)
    hud.update(
      state: bindingState, companionPoint: position, characterSize: view.characterSize,
      visibleFrame: visibleFrame)
  }
}
