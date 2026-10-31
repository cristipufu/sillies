import AppKit
import SilliesCore

/// Coordinates window-drop highlighting, dwell detection, and the radial skill wheel
/// while a companion is picked up and dragged across the workspace.
@MainActor
final class CompanionDragTargetingController {
  static let defaultRadialDwellDelay: Double = 0.24
  private static let radialDwellTolerance: Double = 18
  private static let radialDismissDistance: Double = 148
  private static let radialOppositeHemisphereDismissDistance: Double = 68
  private static let minimumDragDistanceForWheel: Double = 14
  private static let minimumDwellSleepInterval: Double = 0.002

  struct SkillSelection {
    let skill: CompanionSkillKind
    let target: WindowTargetCandidate
  }

  let targets: DragWindowTargetResolver
  let windowSnapshot: DragWindowSnapshot
  let metrics: DragResponseMetrics
  private let radialDwellDelay: Double

  private let radialWheel = RadialWheelController()
  private let windowHighlight = WindowDropHighlightController()
  private var dragDwellTask: Task<Void, Never>?
  private(set) var draggedCompanionID: String?
  private(set) var draggedTarget: WindowTargetCandidate?
  private var radialLayout: RadialSkillMenuLayout?
  private(set) var hoveredSkill: CompanionSkillKind?
  private var dwellAnchor = CGPoint.zero
  private var dwellAnchorTime: TimeInterval = 0
  private var lastPointer = CGPoint.zero
  private var wheelRequested = false
  private var dwellTargetID: UInt32?
  private var cachedExcludedWindowNumbers: Set<Int> = []
  private var isUpdatingSynchronously = false

  var companionLookup: ((String) -> CompanionInstance?)?
  var excludedOverlayWindowNumbers: (() -> Set<Int>)?
  var currentTrackerWindowFrame: (() -> CGRect?)?
  var currentCharacterSize: (() -> Double)?

  init(
    metrics: DragResponseMetrics,
    snapshot: DragWindowSnapshot = DragWindowSnapshot(),
    dropHitTest: DragWindowTargetResolver.HitTest? = nil,
    lookup: DragWindowTargetResolver.Lookup? = nil,
    radialDwellDelay: Double = CompanionDragTargetingController.defaultRadialDwellDelay
  ) {
    self.windowSnapshot = snapshot
    self.metrics = metrics
    self.radialDwellDelay = radialDwellDelay
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

  var usesHardwareBorderOutline: Bool {
    windowHighlight.usesHardwareBorderOutline
  }

  func start() {
    targets.onTargetChanged = { [weak self] target in
      guard let self, !self.isUpdatingSynchronously else { return }
      self.dragTargetChanged(target)
    }
    windowSnapshot.onChange = { [weak self] in self?.targets.invalidateWindowStack() }
  }

  func stop() {
    resetAndCloseOverlays()
    targets.onTargetChanged = nil
    windowSnapshot.onChange = nil
  }

  func refreshWindowSnapshot() { windowSnapshot.refresh() }

  func updateKnownWindow(_ id: CGWindowID?, frame: CGRect?) {
    windowSnapshot.updateKnownWindow(id, frame: frame)
    targets.updateKnownWindow(id, frame: frame)
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
    resetAndHideOverlays()
    draggedCompanionID = pet.definition.id
    cachedExcludedWindowNumbers = excludedWindowNumbers(
      including: excludedOverlayWindowNumbers?() ?? [])
    windowHighlight.prestage(target: seed)
    windowSnapshot.start(seed: seed)
    targets.start(seed: seed)
    dwellAnchor = pointer
    dwellAnchorTime = ProcessInfo.processInfo.systemUptime
    lastPointer = pointer
  }

  func updateDrag(for pet: CompanionInstance, at pointer: CGPoint) {
    lastPointer = pointer
    let excluded =
      cachedExcludedWindowNumbers.isEmpty
      ? excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
      : cachedExcludedWindowNumbers
    if let layout = radialLayout, let target = draggedTarget {
      let distance = hypot(pointer.x - layout.anchor.x, pointer.y - layout.anchor.y)
      let skill = layout.selectedSkill(at: pointer)
      let flippedDownward = (layout.items.first?.center.y ?? layout.anchor.y) < layout.anchor.y
      let movedOppositeToBubbles =
        skill == nil
        && (flippedDownward
          ? (pointer.y - layout.anchor.y > Self.radialOppositeHemisphereDismissDistance)
          : (layout.anchor.y - pointer.y > Self.radialOppositeHemisphereDismissDistance))
      isUpdatingSynchronously = true
      targets.update(at: layout.anchor, excluding: excluded)
      isUpdatingSynchronously = false
      let mismatchedTarget =
        targets.currentTarget != nil && targets.currentTarget?.windowID != target.windowID
      if distance > Self.radialDismissDistance || movedOppositeToBubbles || mismatchedTarget {
        radialLayout = nil
        hoveredSkill = nil
        wheelRequested = false
        radialWheel.hide()
        dwellAnchor = pointer
        dwellAnchorTime = ProcessInfo.processInfo.systemUptime
      } else {
        hoveredSkill = skill
        metrics.measure(.highlight) {
          windowHighlight.show(target: target, hoveredSkill: skill)
        }
        metrics.measure(.wheel) {
          radialWheel.show(layout: layout, hoveredSkill: skill)
        }
        return
      }
    }
    let dragDistance = hypot(
      pet.position.x - pet.pickupPosition.x, pet.position.y - pet.pickupPosition.y)
    guard dragDistance >= Self.minimumDragDistanceForWheel else {
      dragDwellTask?.cancel()
      dragDwellTask = nil
      wheelRequested = false
      windowHighlight.conceal()
      return
    }
    if hypot(pointer.x - dwellAnchor.x, pointer.y - dwellAnchor.y) > Self.radialDwellTolerance {
      wheelRequested = false
      dwellAnchor = pointer
      dwellAnchorTime = ProcessInfo.processInfo.systemUptime
    }
    isUpdatingSynchronously = true
    targets.update(at: pointer, excluding: excluded)
    isUpdatingSynchronously = false
    dragTargetChanged(targets.currentTarget)
  }

  func finishDrag() -> SkillSelection? {
    defer { resetAndHideOverlays() }
    guard let layout = radialLayout, let skill = hoveredSkill, let target = draggedTarget else {
      return nil
    }
    let excluded =
      cachedExcludedWindowNumbers.isEmpty
      ? excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
      : cachedExcludedWindowNumbers
    guard targets.windowIDAtRelease(at: layout.anchor, excluding: excluded) == target.windowID
    else { return nil }
    return SkillSelection(skill: skill, target: target)
  }

  func resetAndHideOverlays() {
    resetTrackingState()
    windowHighlight.hide()
    radialWheel.hide()
  }

  func resetAndCloseOverlays() {
    resetTrackingState()
    windowHighlight.close()
    radialWheel.close()
  }

  private func resetTrackingState() {
    resetDragDwell()
    draggedCompanionID = nil
    cachedExcludedWindowNumbers.removeAll(keepingCapacity: true)
    wheelRequested = false
    targets.stop()
    windowSnapshot.stop()
    draggedTarget = nil
    radialLayout = nil
    hoveredSkill = nil
  }

  private func dragTargetChanged(_ target: WindowTargetCandidate?) {
    guard let id = draggedCompanionID,
      let pet = companionLookup?(id), pet.isPickedUp
    else { return }
    if radialLayout != nil {
      guard target?.windowID != draggedTarget?.windowID else { return }
      radialLayout = nil
      hoveredSkill = nil
      wheelRequested = false
      radialWheel.hide()
    }
    draggedTarget = target
    let pointer = lastPointer
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
      windowHighlight.conceal()
      return
    }
    if dwellTargetID != target.windowID {
      resetDragDwell()
      dwellTargetID = target.windowID
      dwellAnchor = pointer
      dwellAnchorTime = ProcessInfo.processInfo.systemUptime
    }
    metrics.measure(.highlight) { windowHighlight.show(target: target, hoveredSkill: nil) }
    if explicitWheel { wheelRequested = true }
    if wheelRequested {
      openRadialWheel(for: pet, target: target, at: pointer)
    } else if dragDwellTask == nil {
      scheduleDragDwell(for: id)
    }
  }

  private func scheduleDragDwell(for companionID: String) {
    let delay = radialDwellDelay
    dwellAnchorTime = ProcessInfo.processInfo.systemUptime
    dragDwellTask?.cancel()
    dragDwellTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - self.dwellAnchorTime
        let remaining = delay - elapsed
        if remaining <= Self.minimumDwellSleepInterval {
          break
        }
        try? await Task.sleep(for: .seconds(remaining))
      }
      guard !Task.isCancelled else { return }
      self?.handleDragDwellTimeout(for: companionID)
    }
  }

  private func resetDragDwell() {
    dragDwellTask?.cancel()
    dragDwellTask = nil
    dwellTargetID = nil
    wheelRequested = false
  }

  private func handleDragDwellTimeout(for companionID: String) {
    dragDwellTask = nil
    guard draggedCompanionID == companionID, radialLayout == nil, dwellTargetID != nil,
      let pet = companionLookup?(companionID), pet.isPickedUp
    else { return }
    wheelRequested = true
    let excluded =
      cachedExcludedWindowNumbers.isEmpty
      ? excludedWindowNumbers(including: excludedOverlayWindowNumbers?() ?? [])
      : cachedExcludedWindowNumbers
    isUpdatingSynchronously = true
    targets.update(at: lastPointer, excluding: excluded)
    isUpdatingSynchronously = false
    dragTargetChanged(targets.currentTarget)
  }

  private func openRadialWheel(
    for pet: CompanionInstance, target: WindowTargetCandidate, at pointer: CGPoint
  ) {
    dragDwellTask?.cancel()
    dragDwellTask = nil
    let visibleFrame = CompanionPanel.visibleFrame(containing: pointer)
    let layout = RadialSkillMenuLayout(center: pointer, visibleFrame: visibleFrame)
    radialLayout = layout
    wheelRequested = false
    hoveredSkill = nil
    metrics.measure(.highlight) { windowHighlight.show(target: target, hoveredSkill: nil) }
    metrics.measure(.wheel) {
      radialWheel.show(layout: layout, hoveredSkill: nil)
    }
  }
}
