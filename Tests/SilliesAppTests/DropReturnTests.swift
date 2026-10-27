import AppKit
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
    releasedAt: pet.position, pickedUpAt: origin, destination: origin, intent: .returnToPerch)
  pet.dropReturn.begin(for: pet, plan: plan, reducedMotion: false) { landed = true }
  #expect(!landed && pet.isReturningFromDrop)
  #expect(pet.tween?.end == origin && pet.tween?.curve == .accelerating)
  pet.dropReturn.finish(for: pet, reducedMotion: false)
  #expect(landed && !pet.isReturningFromDrop && pet.tween == nil)
  #expect(pet.position == origin)
  #expect(pet.panel.frame.intersection(dropTestWindow).isEmpty)
}

@Test @MainActor func reducedMotionReturnsImmediatelyAndCompletesArrivalOnce() throws {
  let pet = try dropTestCompanion()
  defer { pet.presentation.close() }
  let origin = pet.position
  pet.isPickedUp = true
  pet.place(at: CGPoint(x: origin.x + 90, y: origin.y - 100))
  pet.isPickedUp = false
  let plan = DropReturnPlan(
    releasedAt: pet.position, pickedUpAt: origin, destination: origin, intent: .returnToPerch)
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
      releasedAt: pet.position, pickedUpAt: origin, destination: origin, intent: .returnToPerch),
    reducedMotion: false
  ) { activated = true }
  pet.dropReturn.cancel()
  pet.tween = nil
  pet.dropReturn.finish(for: pet, reducedMotion: false)
  #expect(!activated && !pet.isReturningFromDrop)
}

@Test @MainActor func unselectedDropsReturnWithoutBindingOrCreatingASkillBar() throws {
  let domain = "app.sillies.test.quiet-drop.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = true
  settings.reduceMotion = true
  settings.enabledCharacters = ["mochi"]
  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.start()
  defer { controller.stop() }
  controller.tracker.simulateTrackedWindow(dropTestWindow, windowID: 401)
  let view = try #require(controller.primaryCompanionView)
  let origin = try #require(controller.attachmentDiagnostics.first?.point)

  for delta in [CGPoint(x: 80, y: -100), CGPoint(x: 80, y: 100)] {
    view.onPickup?()
    view.onDrag?(delta)
    view.onDrop?(true)
    #expect(controller.attachmentDiagnostics.first?.point == origin)
    #expect(controller.skills.binding(for: "mochi") == .followingFocusedWindow)
    #expect(controller.diagnostics.visibleHUDCount == 0)
  }

  // Returning without a new choice must preserve a skill the user already started.
  let target = WindowTargetCandidate(
    windowID: 401, processID: 100, appName: "Test", frame: dropTestWindow)
  controller.skills.startSkill(.focus, for: "mochi", companionName: "Mochi", target: target)
  view.onPickup?()
  view.onDrag?(CGPoint(x: 80, y: -100))
  view.onDrop?(true)
  guard case .active(let retained, .focus, _, _, _) = controller.skills.binding(for: "mochi") else {
    Issue.record("An unselected drop cancelled the existing skill")
    return
  }
  #expect(retained.windowID == target.windowID)
  #expect(controller.diagnostics.visibleHUDCount == 1)
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
