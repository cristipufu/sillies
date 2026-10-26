import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func fallDefersLandingAndRestoresExteriorPanelBounds() throws {
  let pet = try dropTestCompanion()
  defer { pet.presentation.close() }
  let origin = pet.position
  pet.isPickedUp = true
  pet.place(at: CGPoint(x: origin.x + 90, y: origin.y + 120))
  pet.isPickedUp = false
  var landed = false
  let plan = DropReturnPlan(
    releasedAt: pet.position, pickedUpAt: origin, destination: origin, selectedSkill: false)
  pet.dropReturn.begin(for: pet, plan: plan, reducedMotion: false) { landed = true }
  #expect(!landed && pet.isReturningFromDrop)
  #expect(pet.tween?.end == origin && pet.tween?.curve == .accelerating)
  pet.dropReturn.finish(for: pet, reducedMotion: false)
  #expect(landed && !pet.isReturningFromDrop && pet.tween == nil)
  #expect(pet.position == origin)
  #expect(pet.panel.frame.intersection(dropTestWindow).isEmpty)
}

@Test @MainActor func reducedMotionReturnsImmediatelyBeforeShowingTheSkillBar() throws {
  let pet = try dropTestCompanion()
  defer { pet.presentation.close() }
  let origin = pet.position
  pet.isPickedUp = true
  pet.place(at: CGPoint(x: origin.x + 90, y: origin.y - 100))
  pet.isPickedUp = false
  let plan = DropReturnPlan(
    releasedAt: pet.position, pickedUpAt: origin, destination: origin, selectedSkill: false)
  var arrivals = 0
  pet.dropReturn.begin(for: pet, plan: plan, reducedMotion: true) {
    arrivals += 1
    #expect(pet.position == origin && !pet.isReturningFromDrop)
  }
  #expect(arrivals == 1 && pet.tween == nil)
  #expect(pet.view.presentationLayer.animationKeys() == nil)
  pet.dropReturn.finish(for: pet, reducedMotion: true)
  #expect(arrivals == 1)
}

@Test @MainActor func cancellingAReturnPreventsStaleLandingOrSkillActivation() throws {
  let pet = try dropTestCompanion()
  defer { pet.presentation.close() }
  let origin = pet.position
  pet.place(at: CGPoint(x: origin.x, y: origin.y + 100))
  var activated = false
  pet.dropReturn.begin(
    for: pet,
    plan: DropReturnPlan(
      releasedAt: pet.position, pickedUpAt: origin, destination: origin, selectedSkill: false),
    reducedMotion: false
  ) { activated = true }
  pet.dropReturn.cancel()
  pet.tween = nil
  pet.dropReturn.finish(for: pet, reducedMotion: false)
  #expect(!activated && !pet.isReturningFromDrop)
}

@Test @MainActor func pendingSkillChoicesKeepTheOriginPerchUntilASkillIsSelected() throws {
  let pet = try dropTestCompanion()
  let origin = WindowTargetCandidate(
    windowID: 1, processID: 10, appName: "Origin", frame: dropTestWindow)
  let candidate = WindowTargetCandidate(
    windowID: 2, processID: 20, appName: "Candidate",
    frame: dropTestWindow.offsetBy(dx: 200, dy: 100))
  pet.selectionPerchTarget = origin
  pet.bindingState = .awaitingSelection(target: candidate, expiresAt: 100)
  #expect(pet.attachmentTarget?.windowID == origin.windowID)
  #expect(pet.bindingState.boundTarget?.windowID == candidate.windowID)
  pet.bindingState = .active(target: candidate, skill: .focus, startedAt: 10)
  #expect(pet.attachmentTarget?.windowID == candidate.windowID)
}

private let dropTestWindow = CGRect(x: 200, y: 150, width: 700, height: 400)

@MainActor
private func dropTestCompanion() throws -> CompanionInstance {
  let definition = try #require(CharacterCatalog().characters.first)
  let pet = CompanionInstance(
    definition: definition, rig: CatRig(), size: 64, seed: 1, transitions: TransitionLibrary())
  let display = CGRect(x: 0, y: 0, width: 1500, height: 1000)
  let surface = PerchSurface(window: dropTestWindow, visibleFrame: display, characterSize: 64)
  pet.surface = surface
  pet.view.configureSurface(pose: .standing, window: dropTestWindow, display: display)
  pet.place(at: surface.point(at: 0.35))
  return pet
}
