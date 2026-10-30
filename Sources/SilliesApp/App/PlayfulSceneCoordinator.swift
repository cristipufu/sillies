import AppKit
import QuartzCore
import SilliesCore

/// Applies finite Core scene plans through companion commands and the existing shared clocks.
@MainActor
final class PlayfulSceneCoordinator {
  enum Availability { case suspended, animated, reducedMotion }
  enum Cancellation {
    case restorePerches, geometryChanging
    case pickup(String)
  }
  private let catalog: PlayfulSceneCatalog
  private let animations: AnimationLibrary
  private let prop = PlayfulPropPresentation()
  private var director: PlayfulSceneDirector
  private var availability: Availability = .suspended
  private var cast: [CompanionInstance] = []
  private var session: PlayfulSceneSession?
  private var phaseIndex: Int?
  private(set) var completedSceneCount = 0
  var activeSceneID: String? { session?.plan.definition.id }
  var isActive: Bool { session != nil }
  var hasVisibleProp: Bool { prop.isVisible }
  var propPreviews: [(NSView, CGRect)] { prop.previews }
  var windowNumbers: Set<Int> { prop.windowNumbers }
  var motionCompanion: CompanionInstance? { needsFrames ? cast.first : nil }
  private var eligibleScenes: [PlayfulSceneDefinition] {
    availability == .reducedMotion
      ? catalog.scenes.filter { $0.layout == .perches } : catalog.scenes
  }
  var nextDeadline: Double? {
    guard availability != .suspended else { return nil }
    if let session, let phaseIndex {
      return session.phaseStart(phaseIndex) + session.plan.definition.phases[phaseIndex].duration
    }
    return director.nextOpportunity
  }
  private var needsFrames: Bool {
    guard let session, let phaseIndex, availability == .animated else { return false }
    let phase = session.plan.definition.phases[phaseIndex]
    if phase.motion != nil || phase.prop == .plane { return true }
    return phase.cues.contains { cue in
      let previous =
        phaseIndex == 0
        ? nil : session.plan.definition.phases[phaseIndex - 1].cues.first { $0.role == cue.role }
      return cue.destination != (previous?.destination ?? .home) || cue.pose != previous?.pose
    }
  }

  init(catalog: PlayfulSceneCatalog, animations: AnimationLibrary, seed: UInt64) {
    self.catalog = catalog
    self.animations = animations
    director = PlayfulSceneDirector(seed: seed)
  }

  func configure(_ availability: Availability, at time: Double) {
    if self.availability != availability { cancel(.restorePerches) }
    self.availability = availability
    if availability == .suspended { director.suspend() } else { director.resume(at: time) }
  }

  func consider(_ opportunity: PlayfulSceneDirector.Opportunity, companions: [CompanionInstance]) {
    guard availability != .suspended, session == nil,
      let plan = director.select(from: eligibleScenes, opportunity: opportunity)
    else { return }
    begin(plan, companions: companions, at: opportunity.time)
  }

  @discardableResult
  func preview(
    _ id: String, opportunity: PlayfulSceneDirector.Opportunity,
    companions: [CompanionInstance]
  ) -> Bool {
    guard availability != .suspended,
      let definition = eligibleScenes.first(where: { $0.id == id }),
      let plan = director.makePlan(definition, opportunity: opportunity)
    else { return false }
    cancel(.restorePerches)
    director.didStart(plan, at: opportunity.time)
    begin(plan, companions: companions, at: opportunity.time)
    return true
  }

  private func begin(_ plan: PlayfulScenePlan, companions: [CompanionInstance], at time: Double) {
    let ids = Set(plan.actors.map { $0.participant.id })
    cast = companions.filter { ids.contains($0.definition.id) }
    guard cast.count == plan.actors.count else {
      cast.removeAll()
      return
    }
    for pet in companions where !pet.isPickedUp && !pet.isReturningFromDrop { pet.clearMotion() }
    for pet in cast { pet.beginPlayfulScene() }
    session = PlayfulSceneSession(plan: plan, at: time)
    advance(at: time)
  }

  func advance(at time: Double) {
    guard let session else { return }
    guard
      !cast.contains(where: {
        $0.isPickedUp || $0.isStashTargeted || !$0.panel.isVisible || $0.bindingState.isBound
      })
    else {
      cancel(.restorePerches)
      return
    }
    guard let index = session.phaseIndex(at: time) else {
      completedSceneCount += 1
      cancel(.restorePerches)
      return
    }
    let phaseChanged = index != phaseIndex
    if phaseChanged {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
    }
    defer { if phaseChanged { CATransaction.commit() } }
    let frames = session.frames(at: time)
    if phaseChanged {
      phaseIndex = index
      let phase = session.plan.definition.phases[index]
      let start = CACurrentMediaTime() + session.phaseStart(index) - time
      for frame in frames {
        cast.first(where: { $0.definition.id == frame.actor.participant.id })?.playSceneClip(
          frame, library: animations, startingAt: start,
          reducedMotion: availability == .reducedMotion)
      }
      prop.prepare(
        .init(
          prop: phase.prop, message: session.plan.message,
          reducedMotion: availability == .reducedMotion,
          startedAt: start, owner: phase.owningRole, motion: phase.motion, duration: phase.duration)
      )
    }
    if availability == .animated {
      for frame in frames {
        cast.first(where: { $0.definition.id == frame.actor.participant.id })?.placeInScene(frame)
      }
    }
    prop.place(
      frames: frames, plan: session.plan, windowLayer: cast.first?.attachedWindowLayer ?? 0,
      progress: (time - session.phaseStart(index)) / session.plan.definition.phases[index].duration)
  }

  func cancel(_ reason: Cancellation) {
    guard let active = session else { return }
    session?.cancel()
    session = nil
    phaseIndex = nil
    prop.hide()
    for pet in cast {
      guard let actor = active.plan.actors.first(where: { $0.participant.id == pet.definition.id })
      else { continue }
      let placement: CompanionInstance.SceneReturn
      switch reason {
      case .restorePerches: placement = .restorePerch
      case .geometryChanging: placement = .awaitGeometry
      case .pickup(let id): placement = pet.definition.id == id ? .keepForPickup : .restorePerch
      }
      pet.endPlayfulScene(at: actor.participant.position, placement: placement)
      pet.displayBehavior(
        pet.behaviorState, using: animations, reducedMotion: availability == .reducedMotion)
    }
    cast.removeAll(keepingCapacity: true)
  }

  func stop() {
    cancel(.restorePerches)
    director.suspend()
    availability = .suspended
    prop.close()
  }
}
