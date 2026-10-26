import AppKit
import SilliesCore

@MainActor
final class CompanionInstance {
  private static let motionSeedOffset: UInt64 = 41

  let definition: CharacterDefinition
  let view: CompanionView
  let panel: CompanionPanel
  let presentation: CompanionPresentation
  let hud = CompanionHUDController()
  let dropReturn = CompanionDropReturn()
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
  var pickupPosition = CGPoint.zero
  var pickupFraction = 0.5
  var pickupWindowTarget: WindowTargetCandidate?
  var selectionPerchTarget: WindowTargetCandidate?
  var pendingDropTarget: Task<Void, Never>?
  var attachedWindowID: CGWindowID?
  var attachedWindowLayer: Int = WindowServerSource.normalWindowLayer
  var bindingState: CompanionBindingState = .followingFocusedWindow
  private var appliedLayoutSize: CGSize = .zero
  private(set) var placementCount = 0

  var attachmentTarget: WindowTargetCandidate? {
    if case .awaitingSelection = bindingState { return selectionPerchTarget }
    return bindingState.boundTarget
  }

  init(
    definition: CharacterDefinition, rig: CharacterRig, size: Double, seed: UInt64,
    transitions: TransitionLibrary
  ) {
    self.definition = definition
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

  func place(at point: CGPoint) {
    placementCount += 1
    position = point
    updateOverlayLevel()
    let layout = view.panelLayout(at: point, attached: !isPickedUp && !isReturningFromDrop)
    let sizeChanged =
      abs(appliedLayoutSize.width - layout.frame.width) > 0.001
      || abs(appliedLayoutSize.height - layout.frame.height) > 0.001
    if sizeChanged {
      appliedLayoutSize = layout.frame.size
      panel.setFrame(layout.frame, display: false)
    } else if abs(panel.frame.minX - layout.frame.minX) > 0.001
      || abs(panel.frame.minY - layout.frame.minY) > 0.001
    {
      panel.setFrameOrigin(layout.frame.origin)
    }
    view.applyPanelLayout(layout)
    view.updateWorldMask()
    refreshHUD()
  }

  func cancelPendingDropTarget() {
    pendingDropTarget?.cancel()
    pendingDropTarget = nil
  }

  func refreshHUD() {
    guard bindingState.isBound, panel.isVisible, !isPickedUp, !isReturningFromDrop,
      !isWaitingForSpace
    else {
      hud.hide()
      return
    }
    let visibleFrame =
      (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    hud.update(
      state: bindingState, companionPoint: position, characterSize: view.characterSize,
      visibleFrame: visibleFrame)
  }
}
