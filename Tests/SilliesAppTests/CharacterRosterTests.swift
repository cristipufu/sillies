import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func bundledCrewHasFourDistinctValidatedCharacters() throws {
  let catalog = try CharacterCatalog()
  #expect(catalog.characters.map(\.id) == ["mochi", "kiko", "pogo", "bolt"])
  #expect(Set(catalog.characters.map(\.renderer)).count == 4)
  try catalog.validateAssets(
    renderers: RendererRegistry(), animations: AnimationLibrary(), transitions: TransitionLibrary())
}

@Test @MainActor func everyCharacterReactionSupportsEveryPoseAndReducedMotion() throws {
  let library = AnimationLibrary()
  let renderers = RendererRegistry()
  for character in try CharacterCatalog().characters {
    let rig = try #require(renderers.make(character.renderer))
    let layerCount = layers(in: rig.root).count
    for pose in [AttachmentPose.standing, .hangingLeft, .hangingRight] {
      rig.setAttachmentPose(pose)
      for reaction in character.reactions {
        let state = BehaviorState(animation: reaction.animation)
        library.apply(state, to: rig, characterID: character.id, reducedMotion: false)
        #expect(layers(in: rig.root).count == layerCount, "Clips must reuse the existing rig")
        if pose.isHanging {
          #expect(rig.hangingArms.animationKeys() == nil, "Upper hand must stay attached")
        }
        library.apply(state, to: rig, characterID: character.id, reducedMotion: true)
        #expect(layers(in: rig.root).allSatisfy { $0.animationKeys() == nil })
        rig.resetPose()
        #expect(layers(in: rig.root).allSatisfy { $0.animationKeys() == nil })
      }
    }
  }
}

@Test @MainActor func boltDisplayAndAntennaResetWhenInterruptedOrStopped() {
  let rig = RobotRig()
  let library = AnimationLibrary()
  library.apply(
    BehaviorState(animation: RobotAnimations.scan), to: rig, characterID: "bolt",
    reducedMotion: false)
  #expect(rig.viewfinder.opacity == 1 && rig.eyes.opacity == 0)
  #expect(rig.viewfinder.animationKeys()?.isEmpty == false)
  library.apply(
    BehaviorState(animation: .listen), to: rig, characterID: "bolt", reducedMotion: false)
  #expect(rig.viewfinder.opacity == 0 && rig.eyes.opacity == 1)
  #expect(rig.viewfinder.animationKeys() == nil)
  #expect(rig.antenna.animationKeys()?.isEmpty == false)
  rig.resetPose()
  #expect(rig.antenna.animationKeys() == nil)
  library.apply(
    BehaviorState(animation: RobotAnimations.scan), to: rig, characterID: "bolt",
    reducedMotion: true)
  #expect(rig.viewfinder.opacity == 1 && rig.viewfinder.animationKeys() == nil)
  rig.resetPose()
  #expect(rig.viewfinder.opacity == 0 && rig.eyes.opacity == 1)
}

@Test @MainActor func newcomerClipsPreserveWindowInertiaAndFixedGrips() {
  let library = AnimationLibrary()
  for (id, rig) in [("pogo", FrogRig() as CharacterRig), ("bolt", RobotRig() as CharacterRig)] {
    rig.setAttachmentPose(.hangingLeft)
    let contact = rig.hangingArms.convert(AttachmentPose.hangingLeft.anchor, to: rig.root)
    rig.workspaceFeedback(lean: 0.12, stretch: 0.04)
    library.apply(
      BehaviorState(animation: .brace), to: rig, characterID: id, reducedMotion: false)
    #expect(rig.workspaceMotion.animation(forKey: "workspaceFeedback") != nil)
    #expect(rig.stage.animation(forKey: "transform.translation.y") != nil)
    #expect(rig.hangingArms.animationKeys() == nil)
    #expect(rig.hangingArms.convert(AttachmentPose.hangingLeft.anchor, to: rig.root) == contact)
  }
}

@Test @MainActor func fourCharacterCrewHasDistinctInteractivePerches() throws {
  let suiteName = "app.sillies.test.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = AppSettings(defaults: defaults)
  let catalog = try CharacterCatalog()
  settings.enabledCharacters = Set(catalog.characters.map(\.id))
  settings.followsWindows = false
  settings.reduceMotion = true
  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.start()
  defer { controller.stop() }
  let attachments = controller.attachmentDiagnostics
  #expect(attachments.count == 4 && attachments.allSatisfy(\.visible))
  for attachment in attachments {
    #expect(
      controller.interactiveArtworkCount(
        at: CGPoint(x: attachment.point.x, y: attachment.point.y + 35)) == 1)
  }
  settings.paused = true
  #expect(controller.diagnostics.visibleCount == 0)
  #expect(
    !controller.diagnostics.movementClockRunning && !controller.diagnostics.decisionClockRunning)
}

@Test @MainActor func addingCatalogEntriesPreservesSavedCrewSelection() throws {
  let suiteName = "app.sillies.test.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(["kiko"], forKey: "characters")
  let settings = AppSettings(defaults: defaults)
  #expect(settings.enabledCharacters == ["kiko"])
  #expect(try CharacterCatalog().characters.count == 4)
}

@MainActor
private func layers(in root: CALayer) -> [CALayer] {
  [root] + (root.sublayers ?? []).flatMap { layers(in: $0) }
}
