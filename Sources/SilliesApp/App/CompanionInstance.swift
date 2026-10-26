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
  var bindingState: CompanionBindingState = .followingFocusedWindow

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

  func place(at point: CGPoint) {
    position = point
    let layout = view.panelLayout(at: point, attached: !isPickedUp && !isReturningFromDrop)
    let tolerance = 0.5 / panel.backingScaleFactor
    if abs(panel.frame.width - layout.frame.width) > tolerance
      || abs(panel.frame.height - layout.frame.height) > tolerance
    {
      panel.setFrame(layout.frame, display: true)
    } else if abs(panel.frame.minX - layout.frame.minX) > tolerance
      || abs(panel.frame.minY - layout.frame.minY) > tolerance
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
    guard panel.isVisible, !isPickedUp, !isReturningFromDrop, !isWaitingForSpace else {
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
