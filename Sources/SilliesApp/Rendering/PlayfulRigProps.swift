import AppKit
import QuartzCore
import SilliesCore

/// Handheld artwork lives under its hand. Shared/world props have a separate presentation owner.
@MainActor
final class PlayfulRigProps {
  private var sceneFrame: PlayfulSceneSession.Frame?
  let monocle: PlayfulMonocle
  let contact: PlayfulContactArtwork
  let sweep: PlayfulSweepArtwork
  let ledge = CALayer()

  init(rig: CharacterRig) {
    monocle = PlayfulMonocle(rig: rig)
    sweep = PlayfulSweepArtwork(rig: rig)
    contact = PlayfulContactArtwork(rig: rig)
    for prop in [ledge] {
      prop.frame = rig.stage.bounds
      prop.name = ArtworkHitTester.decorationName
      rig.stage.addSublayer(prop)
    }
    rig.line(
      on: ledge, points: [CGPoint(x: 39, y: 43), CGPoint(x: 35, y: 20)], color: "84675B", width: 5)
    rig.line(
      on: ledge, points: [CGPoint(x: 89, y: 43), CGPoint(x: 93, y: 20)], color: "84675B", width: 5)
    rig.pill(on: ledge, CGRect(x: 27, y: 40, width: 74, height: 7), "B58E74", radius: 3)
    rig.pill(on: ledge, CGRect(x: 29, y: 44, width: 70, height: 2), "E4C4A5", radius: 1)
    reset()
  }

  func configureScene(_ frame: PlayfulSceneSession.Frame) { sceneFrame = frame }

  func clamber() {
    guard let sceneFrame else { return }
    contact.clamber(actor: sceneFrame.actor, duration: sceneFrame.duration)
  }

  func reset() {
    sweep.reset()
    contact.reset()
    for layer in [monocle.layer, ledge] {
      layer.removeAllAnimations()
      layer.transform = CATransform3DIdentity
      layer.opacity = 0
    }
  }
}
