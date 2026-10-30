import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func playfulCatalogResolvesEveryCharacterAndSceneClip() throws {
  let characters = try CharacterCatalog()
  let catalog = try PlayfulSceneCatalog()
  let animations = AnimationLibrary()
  try catalog.validate(characters: characters, animations: animations)
  for character in characters.characters {
    let rig = try #require(RendererRegistry().make(character.renderer))
    let profile = try #require(character.playful)
    for scene in catalog.scenes {
      for cue in scene.phases.flatMap(\.cues) {
        let state = BehaviorState(animation: profile.animation(for: cue.animation))
        animations.apply(state, to: rig, characterID: character.id, reducedMotion: false)
        animations.apply(state, to: rig, characterID: character.id, reducedMotion: true)
        rig.resetPose()
        #expect(rig.stage.animationKeys() == nil)
      }
    }
  }
}

@Test @MainActor func playfulScenesYieldToPickupPauseAndWindowGeometry() throws {
  let domain = "app.sillies.test.scenes.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let settings = AppSettings(defaults: defaults)
  settings.enabledCharacters = ["mochi", "kiko"]
  settings.activity = .playful
  settings.followsWindows = true
  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.start()
  defer { controller.stop() }
  let screen = CompanionPanel.visibleFrame()
  let window = CGRect(
    x: screen.minX + 180, y: screen.minY + 80, width: 650, height: screen.height - 340)
  controller.tracker.simulateTrackedWindow(window, windowID: 301)
  let startedDance = controller.previewPlayfulScene("dance")
  #expect(startedDance)
  // Stationary dancing is compositor-driven; a separate app frame loop is unnecessary.
  #expect(!controller.diagnostics.movementClockRunning)
  controller.primaryCompanionView?.onPickup?()
  #expect(!controller.playfulScenes.isActive)
  controller.primaryCompanionView?.onDrop?(true)
  settings.reduceMotion = true
  let startedProtest = controller.previewPlayfulScene("protest")
  #expect(startedProtest)
  settings.paused = true
  #expect(!controller.playfulScenes.isActive)
  #expect(!controller.playfulScenes.hasVisibleProp)
  #expect(!controller.diagnostics.decisionClockRunning)
  settings.paused = false
  settings.reduceMotion = false
  controller.tracker.simulateTrackedWindow(window, windowID: 301)
  let startedMonocle = controller.previewPlayfulScene("monocle")
  #expect(startedMonocle)
  let placementsBeforeMovement = controller.totalPlacementCount
  controller.tracker.simulateTrackedWindow(window.offsetBy(dx: 20, dy: 10), windowID: 301)
  #expect(
    controller.totalPlacementCount - placementsBeforeMovement == settings.enabledCharacters.count)
  #expect(!controller.playfulScenes.isActive)
  #expect(
    controller.attachmentDiagnostics.allSatisfy {
      !$0.frame.intersects(window.offsetBy(dx: 20, dy: 10))
    })
}

@Test @MainActor func playfulTugKeepsBothHandsOnTheRopeForEveryCharacter() throws {
  let catalog = try CharacterCatalog()
  let animations = AnimationLibrary()
  for character in catalog.characters {
    let rig = try #require(RendererRegistry().make(character.renderer))
    animations.apply(
      BehaviorState(animation: "scene.tug"), to: rig,
      characterID: character.id, reducedMotion: false)
    rig.articulatePlayfulPose()
    let contact = rig.preparePlayfulProps().contact
    #expect(contact.gripPoints == PlayfulPropLayout.tugGripsInDesignSpace)
    #expect(contact.layer.opacity == 1)
    #expect(rig.leftArm.opacity == 0 && rig.rightArm.opacity == 0)
    rig.resetPose()
  }
}

@Test @MainActor func playfulPropRestoresTrackingExclusionAfterRestart() throws {
  let prop = PlayfulPropPresentation()
  defer { prop.close() }
  prop.close()
  prop.prepare(.init(prop: .sign, message: "A tiny sign", reducedMotion: true, startedAt: 0))
  #expect(WindowTrackingExclusions.transparentOverlays.contains(UInt32(prop.windowNumber)))
  prop.close()
  #expect(!WindowTrackingExclusions.transparentOverlays.contains(UInt32(prop.windowNumber)))
}

@Test @MainActor func playfulRopeUsesTheExistingSideGripAndRestoresItsPerch() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  try fixture.start("rope-descent")
  fixture.coordinator.advance(at: 4)
  let actor = try #require(fixture.companions.first { $0.isPerformingScene })
  #expect(actor.attachmentPose == .hangingRight)
  #expect(actor.view.rig.hangingArms.opacity == 1)
  #expect(actor.view.rig.leftArm.opacity == 0 && actor.view.rig.rightArm.opacity == 0)
  #expect(actor.view.rig.secondaryGrip.animation(forKey: "transform.translation.y") != nil)
  #expect(!actor.panel.frame.intersects(fixture.window))
  fixture.coordinator.cancel(.restorePerches)
  #expect(actor.attachmentPose == .standing)
  #expect(actor.view.rig.hangingArms.opacity == 0)
}
