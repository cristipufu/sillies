import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

struct NewCompanionFixture: Sendable {
  let id: String
  let renderer: String
  let signature: AnimationID
  let flourish: AnimationID

  static let all: [Self] = [
    .init(id: "novi", renderer: "alien", signature: "novi.scan", flourish: "novi.float"),
    .init(id: "lumi", renderer: "witch", signature: "lumi.conjure", flourish: "lumi.catchHat"),
    .init(id: "rook", renderer: "knight", signature: "rook.polish", flourish: "rook.visorSlip"),
    .init(id: "flick", renderer: "candle", signature: "flick.warmHands", flourish: "flick.glow"),
    .init(id: "leon", renderer: "spartan", signature: "leon.training", flourish: "leon.victory"),
    .init(id: "gizmo", renderer: "goblin", signature: "gizmo.tinker", flourish: "gizmo.mishap"),
    .init(id: "orbit", renderer: "astronaut", signature: "orbit.check", flourish: "orbit.moonstep"),
    .init(id: "mimo", renderer: "mime", signature: "mimo.glass", flourish: "mimo.bow"),
  ]
}

@Test @MainActor func newCompanionDetailsSurviveSharedActionsAndResetCleanly() throws {
  let animations = AnimationLibrary()
  for character in NewCompanionFixture.all {
    let rig = try #require(RendererRegistry().make(character.renderer))
    _ = rig.preparePlayfulProps()
    let count = descendants(of: rig.root).count
    for pose in [AttachmentPose.standing, .hangingLeft, .hangingRight] {
      rig.setAttachmentPose(pose)
      for clip in [
        character.signature, character.flourish, .walk, .listen, .sleep,
        "scene.dance", "scene.tug", "scene.sweep", "scene.parachute",
      ] {
        animations.apply(
          .init(animation: clip), to: rig, characterID: character.id, reducedMotion: false)
        let layers = descendants(of: rig.root)
        #expect(layers.count == count, "Clips must not allocate artwork")
        #expect(layers.contains { !($0.animationKeys() ?? []).isEmpty })
        if pose.isHanging { #expect(rig.hangingArms.animationKeys() == nil) }
        animations.apply(
          .init(animation: clip), to: rig, characterID: character.id, reducedMotion: true)
        #expect(layers.allSatisfy { $0.animationKeys() == nil })
        rig.resetPose()
        #expect(layers.allSatisfy { $0.animationKeys() == nil })
        #expect(layers.count == count)
      }
    }
  }
}

@Test @MainActor func newCompanionSpeechUsesAVisibleMouthAndRestoresItsExpression() throws {
  for character in NewCompanionFixture.all {
    let rig = try #require(RendererRegistry().make(character.renderer))
    let face = descendants(of: rig.head)
    let restingOpacities = face.map(\.opacity)
    rig.speechAnimation.update(level: 0.8)
    #expect(face.map(\.opacity) != restingOpacities, "Speech must change the visible mouth")
    #expect(rig.head.animation(forKey: "speech.nod") != nil)
    rig.resetPose()
    #expect(face.map(\.opacity) == restingOpacities)
    #expect(rig.head.animationKeys() == nil)
  }
}

@Test @MainActor func newCompanionEffectsStayOutsidePickupHitRegions() {
  let hitTester = ArtworkHitTester()
  let alien = AlienRig()
  alien.scanGlow.opacity = 1
  #expect(!hitTester.containsArtwork(in: alien.root, at: CGPoint(x: 118, y: 87)))
  let witch = WitchRig()
  witch.spellStar.opacity = 1
  witch.spellStar.position = CGPoint(x: 117, y: 75)
  #expect(!hitTester.containsArtwork(in: witch.root, at: CGPoint(x: 117, y: 75)))
  witch.spellStar.name = nil
  #expect(hitTester.containsArtwork(in: witch.root, at: CGPoint(x: 117, y: 75)))
  let candle = CandleRig()
  #expect(!hitTester.containsArtwork(in: candle.root, at: CGPoint(x: 89, y: 108)))
  let goblin = GoblinRig()
  goblin.steam.opacity = 1
  goblin.steam.position = CGPoint(x: 117, y: 117)
  #expect(!hitTester.containsArtwork(in: goblin.root, at: CGPoint(x: 117, y: 117)))
  let astronaut = AstronautRig()
  astronaut.thrusters.opacity = 1
  #expect(!hitTester.containsArtwork(in: astronaut.root, at: CGPoint(x: 29, y: 30)))
  let mime = MimeRig()
  mime.contactMarks.opacity = 1
  #expect(!hitTester.containsArtwork(in: mime.root, at: CGPoint(x: 19, y: 108)))
  for rig in [alien, witch, candle, KnightRig(), SpartanRig(), goblin, astronaut, mime]
    as [CharacterRig]
  {
    #expect(hitTester.containsArtwork(in: rig.root, at: CGPoint(x: 64, y: 75)))
  }
}

@Test @MainActor func newCompanionSignatureTimingIsFiniteAndReturnsToRest() throws {
  let library = AnimationLibrary()
  for character in NewCompanionFixture.all {
    let rig = try #require(RendererRegistry().make(character.renderer))
    for clip in [character.signature, character.flourish] {
      library.apply(
        .init(animation: clip), to: rig, characterID: character.id, reducedMotion: false)
      for layer in descendants(of: rig.root) {
        for key in layer.animationKeys() ?? [] {
          let animation = try #require(layer.animation(forKey: key))
          #expect(animation.duration > 0 && animation.duration.isFinite)
          if let keyframes = animation as? CAKeyframeAnimation {
            let times = try #require(keyframes.keyTimes).map(\.doubleValue)
            let values = try #require(keyframes.values as? [NSNumber]).map(\.doubleValue)
            #expect(times.count == values.count)
            #expect(times.first == 0 && times.last == 1)
            #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
            #expect(values.allSatisfy { $0.isFinite })
          }
        }
      }
      rig.resetPose()
      #expect(descendants(of: rig.root).allSatisfy { $0.animationKeys() == nil })
    }
  }
}

@MainActor
private func descendants(of layer: CALayer) -> [CALayer] {
  [layer] + (layer.sublayers ?? []).flatMap { descendants(of: $0) }
}
