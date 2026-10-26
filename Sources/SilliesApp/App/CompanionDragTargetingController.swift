import AppKit
import SilliesCore

/// Coordinates window-drop highlighting, dwell detection, and the radial skill wheel
/// while a companion is picked up and dragged across the workspace.
@MainActor
final class CompanionDragTargetingController {
  private static let radialDwellDelay: Double = 0.24
  private static let radialDwellTolerance: Double = 18
  private static let radialDismissDistance: Double = 148
  private static let minimumDragDistanceForWheel: Double = 14

  struct DropEvaluation {
    let selectedSkill: CompanionSkillKind?
    let radialWasOpen: Bool
    let cachedTarget: WindowTargetCandidate?
    let pendingDrop: DragWindowTargetResolver.DropTarget?
  }

  let targets: DragWindowTargetResolver
  let windowSnapshot: DragWindowSnapshot
  let metrics: DragResponseMetrics

  private let radialWheel = RadialWheelController()
  private let windowHighlight = WindowDropHighlightController()
  private var dragDwellTimer: Timer?
  private(set) var draggedCompanionID: String?
  private(set) var draggedTarget: WindowTargetCandidate?
  private var radialLayout: RadialSkillMenuLayout?
  private(set) var hoveredSkill: CompanionSkillKind?
  private var dwellAnchor = CGPoint.zero
  private var wheelRequested = false
  private var dwellTargetID: UInt32?

  var companionLookup: ((String) -> CompanionInstance?)?
  var excludedOverlayWindowNumbers: (() -> Set<Int>)?
  var currentTrackerWindowFrame: (() -> CGRect?)?
  var currentCharacterSize: (() -> Double)?

  init(
    metrics: DragResponseMetrics,
    snapshot: DragWindowSnapshot = DragWindowSnapshot(),
    dropHitTest: DragWindowTargetResolver.HitTest? = nil,
    lookup: DragWindowTargetResolver.Lookup? = nil
  ) {
    self.windowSnapshot = snapshot
    self.metrics = metrics
    let liveDropHitTest: DragWindowTargetResolver.HitTest =
      dropHitTest ?? { point, below in
        metrics.measure(.releaseHitTest) {
          NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
        }
      }
    if let lookup {
      self.targets = DragWindowTargetResolver(
        hitTest: { point, below in
          metrics.measure(.hitTest) { snapshot.hitTest(at: point, below: below) }
        },
        dropHitTest: liveDropHitTest,
        lookup: lookup)
    } else {
      self.targets = DragWindowTargetResolver(
        hitTest: { point, below in
          metrics.measure(.hitTest) { snapshot.hitTest(at: point, below: below) }
        },
        dropHitTest: liveDropHitTest)
    }
  }

  var diagnostics: (windowID: UInt32?, highlight: Bool, wheel: Bool) {
    (draggedTarget?.windowID, windowHighlight.isVisible, radialWheel.isVisible)
  }

  func start() {
    targets.onTargetChanged = { [weak self] target in self?.dragTargetChanged(target) }
    windowSnapshot.onChange = { [weak self] in self?.targets.invalidateWindowStack() }
  }

  func stop() {
    clear(closeWheel: true)
    targets.onTargetChanged = nil
    windowSnapshot.onChange = nil
  }

  func prepareOverlays() {
    windowHighlight.prepare()
    radialWheel.prepare()
  }

  func excludedWindowNumbers(including baseWindowNumbers: Set<Int>) -> Set<Int> {
    var excluded = baseWindowNumbers
    if let wheelNumber = radialWheel.windowNumber {
      excluded.insert(wheelNumber)
    }
    if let highlightNumber = windowHighlight.windowNumber {
      excluded.insert(highlightNumber)
    }
    return excluded
  }

  func beginDrag(
    for pet: CompanionInstance, seed: WindowTargetCandidate?, pointer: CGPoint
  ) {
    clear(closeWheel: false)
    draggedCompanionID = pet.definition.id
    windowSnapshot.start(seed: seed)
    targets.start()
    dwellAnchor = pointer
  }

  func updateDrag(for pet: CompanionInstance, at pointer: CGPoint) {
    if let layout = radialLayout, let target = draggedTarget {
      let distance = hypot(pointer.x - layout.anchor.x, pointer.y - layout.anchor.y)
      if distance > Self.radialDismissDistance {
        radialLayout = nil
        hoveredSkill = nil
        wheelRequested = false
        radialWheel.hide()
        dwellAnchor = pointer
      } else {
        let skill = layout.selectedSkill(at: pointer)
        hoveredSkill = skill
        metrics.measure(.highlight) {
          windowHighlight.show(target: target, hoveredSkill: skill)
        }
        metrics.measure(.wheel) {
          radialWheel.show(
            companionName: pet.definition.name, target: target, layout: layout, hoveredSkill: skill)
        }
        return
      }
    }
    let dragDistance = hypot(
      pet.position.x - pet.pickupPosition.x, pet.position.y - pet.pickupPosition.y)
    guard dragDistance >= Self.minimumDragDistanceForWheel else {
      dragDwellTimer?.invalidate()
      dragDwellTimer = nil
      wheelRequested = false
      windowHighlight.hide()
      return
    }
    if hypot(pointer.x - dwellAnchor.x, pointer.y - dwellAnchor.y) > Self.radialDwellTolerance {
      wheelRequested = false
      dwellAnchor = pointer
      dragDwellTimer?.invalidate()
      dragDwellTimer = nil
    }
    let excluded = excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
    targets.update(at: pointer, excluding: excluded)
    dragTargetChanged(targets.currentTarget)
  }

  func evaluateDrop(dragged: Bool, at pointer: CGPoint) -> DropEvaluation {
    let excluded = excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
    let selectedSkill = hoveredSkill
    let radialWasOpen = radialLayout != nil
    let dropPoint = radialLayout?.anchor ?? pointer
    let pendingDrop =
      dragged
      ? targets.dropTarget(at: dropPoint, excluding: excluded) : nil
    let cachedTarget: WindowTargetCandidate?
    if dragged {
      if radialWasOpen, let draggedTarget,
        pendingDrop == nil || pendingDrop?.windowID == draggedTarget.windowID
      {
        cachedTarget = draggedTarget
      } else {
        cachedTarget = pendingDrop?.cached
      }
    } else {
      cachedTarget = nil
    }
    clear(closeWheel: false)
    return DropEvaluation(
      selectedSkill: selectedSkill,
      radialWasOpen: radialWasOpen,
      cachedTarget: cachedTarget,
      pendingDrop: pendingDrop)
  }

  func clear(closeWheel: Bool) {
    resetDragDwell()
    draggedCompanionID = nil
    wheelRequested = false
    targets.stop()
    windowSnapshot.stop()
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

  private func dragTargetChanged(_ target: WindowTargetCandidate?) {
    guard radialLayout == nil, let id = draggedCompanionID,
      let pet = companionLookup?(id), pet.isPickedUp
    else { return }
    draggedTarget = target
    let pointer = NSEvent.mouseLocation
    let modifiers = NSEvent.modifierFlags
    let explicitWheel = modifiers.contains(.option) || modifiers.contains(.command)
    let size = currentCharacterSize?() ?? 64
    let originFrame = pet.pickupWindowTarget?.frame ?? currentTrackerWindowFrame?()
    guard let target,
      explicitWheel
        || DropReturnPlan.shouldShowDragControls(
          targetFrame: target.frame,
          isSameTargetAsAttached: target.windowID == pet.attachedWindowID,
          originWindowFrame: originFrame,
          pointer: pointer,
          companionPoint: pet.position,
          characterSize: size)
    else {
      resetDragDwell()
      windowHighlight.hide()
      return
    }
    if dwellTargetID != target.windowID {
      resetDragDwell()
      dwellTargetID = target.windowID
      dwellAnchor = pointer
    }
    metrics.measure(.highlight) { windowHighlight.show(target: target, hoveredSkill: nil) }
    if explicitWheel { wheelRequested = true }
    if wheelRequested {
      openRadialWheel(for: pet, target: target, at: pointer)
    } else if dragDwellTimer == nil {
      scheduleDragDwell(for: id)
    }
  }

  private func scheduleDragDwell(for companionID: String) {
    let timer = Timer(timeInterval: Self.radialDwellDelay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleDragDwellTimeout(for: companionID) }
    }
    timer.tolerance = 0.02
    RunLoop.main.add(timer, forMode: .common)
    dragDwellTimer = timer
  }

  private func resetDragDwell() {
    dragDwellTimer?.invalidate()
    dragDwellTimer = nil
    dwellTargetID = nil
    wheelRequested = false
  }

  private func handleDragDwellTimeout(for companionID: String) {
    dragDwellTimer = nil
    guard draggedCompanionID == companionID, radialLayout == nil, dwellTargetID != nil,
      let pet = companionLookup?(companionID), pet.isPickedUp
    else { return }
    wheelRequested = true
    let excluded = excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
    targets.update(at: NSEvent.mouseLocation, excluding: excluded)
    dragTargetChanged(targets.currentTarget)
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
    wheelRequested = false
    hoveredSkill = nil
    metrics.measure(.highlight) { windowHighlight.show(target: target, hoveredSkill: nil) }
    metrics.measure(.wheel) {
      radialWheel.show(
        companionName: pet.definition.name, target: target, layout: layout, hoveredSkill: nil)
    }
  }
}
