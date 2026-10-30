import AppKit
import SilliesCore

/// One placement transaction. Pending positions cannot escape into another surface update.
@MainActor
struct CompanionSurfacePlacement {
  enum Mode { case immediate, animated }
  enum Outcome {
    case awaitingWindow, unavailable
    case positioned(PerchSurface.Edge)
  }

  struct Environment {
    let window: CGRect?
    let windowID: CGWindowID?
    let windowLayer: Int
    let followsWindows: Bool
    let isAwaitingWindow: Bool
    let isRunning: Bool
    let reducedMotion: Bool
    let isLowPower: Bool
    let characterSize: Double
    let geometryChange: WindowGeometryChange?
  }

  private struct PresentationContext {
    let targetWindow: (frame: CGRect?, windowID: CGWindowID?, layer: Int)
    let visibleFrame: CGRect
    let mode: Mode
  }

  private let companions: [CompanionInstance]
  private let environment: Environment
  private let animations: AnimationLibrary
  private var pendingPlacements: [ObjectIdentifier: PerchAttachmentChange.Transition] = [:]
  private var shouldRun: Bool { environment.isRunning }
  private var reducedMotion: Bool { environment.reducedMotion }

  init(companions: [CompanionInstance], environment: Environment, animations: AnimationLibrary) {
    self.companions = companions
    self.environment = environment
    self.animations = animations
  }

  @MainActor
  private struct SurfaceUpdateContext {
    let window: CGRect?
    let windowID: CGWindowID?
    let windowLayer: Int
    let screen: NSScreen?
    let mode: Mode
    private var visibleFrames: [ObjectIdentifier: CGRect] = [:]

    init(window: CGRect?, windowID: CGWindowID?, windowLayer: Int, mode: Mode) {
      self.window = window
      self.windowID = windowID
      self.windowLayer = windowLayer
      screen = CompanionSurfacePlacement.preferredScreen(for: window)
      self.mode = mode
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

  private static func preferredScreen(for frame: CGRect?) -> NSScreen? {
    frame.flatMap { rect in
      NSScreen.screens.max { lhs, rhs in
        let a = lhs.frame.intersection(rect)
        let b = rhs.frame.intersection(rect)
        return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
      }
    } ?? NSScreen.main ?? NSScreen.screens.first
  }

  mutating func update(mode: Mode) -> Outcome {
    let defaultWindow = environment.followsWindows ? environment.window : nil
    let defaultWindowID = environment.followsWindows ? environment.windowID : nil
    let defaultWindowLayer =
      environment.followsWindows ? environment.windowLayer : WindowServerSource.normalWindowLayer
    let hasBoundCompanion = companions.contains { $0.bindingState.isBound }
    if environment.followsWindows && (defaultWindow == nil || defaultWindowID == nil)
      && !hasBoundCompanion
    {
      guard !environment.isAwaitingWindow else { return .awaitingWindow }
      hideAllCompanionsWhenNoWindowTracked()
      return .unavailable
    }
    pendingPlacements.removeAll(keepingCapacity: true)
    var context = SurfaceUpdateContext(
      window: defaultWindow, windowID: defaultWindowID, windowLayer: defaultWindowLayer,
      mode: mode)
    var needsSurfaceArrangement = mode == .immediate
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
    return .positioned(location)
  }

  private mutating func hideAllCompanionsWhenNoWindowTracked() {
    pendingPlacements.removeAll(keepingCapacity: true)
    let immediately = reducedMotion || environment.isLowPower
    for pet in companions {
      pet.detachFromWindow(immediately: immediately)
    }
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

  private mutating func updateCompanionSurface(
    _ pet: CompanionInstance,
    at index: Int,
    context: inout SurfaceUpdateContext
  ) -> Bool {
    guard pet.isAttachmentVisible || pet.isPickedUp else {
      pet.hideForUnavailableSurface()
      return false
    }
    let targetWindow = resolveTargetWindow(
      for: pet,
      defaultWindow: context.window,
      defaultWindowID: context.windowID,
      defaultLayer: context.windowLayer)
    if environment.followsWindows && (targetWindow.frame == nil || targetWindow.windowID == nil) {
      if pet.attachmentTarget == nil && environment.isAwaitingWindow {
        return false
      }
      pet.detachFromWindow(immediately: reducedMotion || environment.isLowPower)
      return false
    }
    let screen =
      targetWindow.frame == context.window
      ? context.screen : Self.preferredScreen(for: targetWindow.frame)
    guard let screen else { return false }
    let visibleFrame = context.visibleFrame(for: screen)
    let surface = PerchSurface(
      window: targetWindow.frame, visibleFrame: visibleFrame,
      characterSize: environment.characterSize,
      preferRight: index % 2 == 1)
    let change = PerchAttachmentChange(
      previous: pet.attachmentSnapshot, surface: surface, windowID: targetWindow.windowID,
      fallbackFraction: Double(index + 1) / Double(companions.count + 1))
    return apply(
      change, to: pet,
      context: .init(targetWindow: targetWindow, visibleFrame: visibleFrame, mode: context.mode))
  }

  private mutating func apply(
    _ change: PerchAttachmentChange, to pet: CompanionInstance,
    context: PresentationContext
  ) -> Bool {
    let targetWindow = context.targetWindow
    let surface = change.surface
    let requiresArrangement = change.needsArrangement || pet.tween != nil || pet.isWaitingForSpace
    pet.updateAttachment(
      .init(surface: surface, windowID: targetWindow.windowID, windowLayer: targetWindow.layer))
    let poseChanged = pet.configureSurface(
      surface, window: targetWindow.frame, display: context.visibleFrame)
    guard surface.isAvailable || pet.isPickedUp else {
      pet.hideForUnavailableSurface()
      return requiresArrangement
    }
    if shouldRun && !pet.isPickedUp {
      if pet.isReturningFromDrop && change.transition == .unchanged {
        pet.refreshWorldMask()
        return requiresArrangement
      }
      if change.transition != .unchanged {
        pet.stagePlacement(at: change.target)
        pendingPlacements[ObjectIdentifier(pet)] = change.transition
      } else {
        pet.refreshWorldMask()
        pet.refreshHUD()
        if !pet.isWaitingForSpace {
          pet.presentation.show(
            reattached: false, reducedMotion: reducedMotion || environment.isLowPower)
        }
      }
    } else if pet.isPickedUp {
      pet.refreshWorldMask()
    }
    if !pet.isPickedUp && change.transition != .unchanged {
      applySurfaceMotionFeedback(
        to: pet, change: change, mode: context.mode)
    }
    if shouldRun, poseChanged, !pet.isPickedUp {
      pet.displayBehavior(
        pet.behaviorState, using: animations,
        reducedMotion: reducedMotion || environment.isLowPower)
    }
    return requiresArrangement
  }

  private func applySurfaceMotionFeedback(
    to pet: CompanionInstance,
    change: PerchAttachmentChange,
    mode: Mode
  ) {
    pet.clearMotion()
    if change.transition == .reattached {
      pet.resetWorkspaceFeedback()
    } else if mode == .animated, let geometry = environment.geometryChange, !reducedMotion {
      let feedback = WindowMotionFeedback(
        edge: change.surface.edge, horizontalSpeed: geometry.horizontalSpeed,
        verticalSpeed: geometry.verticalSpeed, widthSpeed: geometry.widthSpeed,
        resized: geometry.resized)
      pet.applyWorkspaceFeedback(feedback)
    }
  }

  private mutating func arrangeRestingCompanionsOnSurfaces() {
    var arrangedSurfaces: [PerchSurface] = []
    for pet in companions where pet.tween == nil && pet.isAttachmentVisible {
      guard let surface = pet.surface, !arrangedSurfaces.contains(surface) else { continue }
      if settleRestingGroup(on: surface, mode: .immediate) {
        arrangedSurfaces.append(surface)
      } else {
        settleAtFreePerch(pet, mode: .immediate)
      }
    }
  }

  private mutating func flushPendingPlacements() {
    guard !pendingPlacements.isEmpty else { return }
    for pet in companions {
      guard let reattached = pendingPlacements.removeValue(forKey: ObjectIdentifier(pet)) else {
        continue
      }
      pet.place(at: pet.position)
      if !pet.isWaitingForSpace {
        pet.presentation.show(
          reattached: reattached == .reattached,
          reducedMotion: reducedMotion || environment.isLowPower)
      }
    }
  }

  func reservations(excluding pet: CompanionInstance) -> [PerchReservation] {
    companions.compactMap { other in
      guard other !== pet, other.isAttachmentVisible, !other.isWaitingForSpace,
        let surface = other.surface, surface.isAvailable
      else { return nil }
      let point =
        other.isPickedUp || other.isReturningFromDrop
        ? surface.point(at: other.pickupFraction)
        : surface.clamped(other.tween?.end ?? other.position)
      return PerchReservation(point: point, surface: surface)
    }
  }

  mutating func settleAtFreePerch(_ pet: CompanionInstance, mode: Mode) {
    guard shouldRun, pet.isAttachmentVisible, !pet.isPickedUp, !pet.isReturningFromDrop,
      !pet.isStashTargeted,
      let surface = pet.surface, surface.isAvailable
    else { return }
    guard
      let target = PerchSpacing.nearestAvailablePoint(
        to: surface.clamped(pet.position), on: surface,
        occupied: reservations(excluding: pet))
    else {
      if !settleRestingGroup(on: surface, mode: mode) { waitForPerchSpace(pet) }
      return
    }
    placeAtRestingTarget(pet, target: target, mode: mode)
  }

  private mutating func settleRestingGroup(on surface: PerchSurface, mode: Mode) -> Bool {
    guard shouldRun, surface.isAvailable else { return false }
    let group = companions.filter { $0.surface == surface && $0.isAttachmentVisible }
    guard group.count > 1,
      group.allSatisfy({ !$0.isPickedUp && !$0.isReturningFromDrop && $0.tween == nil })
    else { return false }
    let targets = PerchSpacing.restingPoints(near: group.map(\.position), on: surface)
    for (pet, target) in zip(group, targets) {
      if let target {
        placeAtRestingTarget(pet, target: target, mode: mode)
      } else {
        waitForPerchSpace(pet)
      }
    }
    return true
  }

  private mutating func waitForPerchSpace(_ pet: CompanionInstance) {
    pendingPlacements.removeValue(forKey: ObjectIdentifier(pet))
    pet.waitForPerchSpace()
  }

  private mutating func placeAtRestingTarget(
    _ pet: CompanionInstance, target: CGPoint, mode: Mode
  ) {
    let pendingReattach = pendingPlacements.removeValue(forKey: ObjectIdentifier(pet))
    let settlement = PerchSettlement(from: pet.position, to: target)
    if pet.isWaitingForSpace {
      pet.resumePerching(at: target)
      pet.presentation.show(
        reattached: pendingReattach == .reattached,
        reducedMotion: reducedMotion || environment.isLowPower)
      pet.refreshHUD()
    } else if pendingReattach != nil
      || settlement.requiresMovement
    {
      if mode == .animated, pendingReattach == nil, !reducedMotion, !environment.isLowPower {
        pet.move(
          to: target, duration: settlement.duration, arcHeight: 0,
          at: ProcessInfo.processInfo.systemUptime)
      } else {
        pet.place(at: target)
      }
      if let reattached = pendingReattach, !pet.isWaitingForSpace {
        pet.presentation.show(
          reattached: reattached == .reattached,
          reducedMotion: reducedMotion || environment.isLowPower)
      }
    }
  }

}
