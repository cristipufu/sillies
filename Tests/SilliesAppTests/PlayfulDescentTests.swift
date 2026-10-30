import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func playfulVoluntaryDescentPlantsHandsAndStaysCloseToTheCorner() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("edge-climb")
  let session = PlayfulSceneSession(plan: plan, at: 0)
  let index = try #require(
    plan.definition.phases.firstIndex { $0.cues.contains { $0.travel == .cornerLowering } })
  let start = session.phaseStart(index)
  let duration = plan.definition.phases[index].duration
  let actor = try #require(plan.actors.first)
  let hanging = actor.point(for: .outside, pose: .hangingRight)
  let motion = PlayfulClamberMotion(actor: actor, direction: .lowerDown)
  let scale = actor.participant.surface.presentationSize / 100
  var previous = actor.corner
  var planted: [CGPoint] = []

  try fixture.start("edge-climb")
  let pet = try #require(fixture.companions.first { $0.isPerformingScene })
  for sample in 0...100 {
    let progress = Double(sample) / 100
    let time = start + duration * progress
    let frame = try #require(session.frames(at: time).first)
    fixture.coordinator.advance(at: time)
    #expect(frame.position.x >= previous.x - 0.01)
    #expect(frame.position.x <= hanging.x + 0.01)
    #expect(hypot(frame.position.x - previous.x, frame.position.y - previous.y) < 4)
    #expect(!pet.panel.frame.intersects(fixture.window))
    #expect(fixture.coordinator.windowNumbers.isEmpty)
    let localFeet = pet.view.rig.stage.convert(AttachmentPose.standing.anchor, to: pet.view.layer)
    let worldFeet = CGPoint(
      x: localFeet.x + pet.panel.frame.minX, y: localFeet.y + pet.panel.frame.minY)
    #expect(hypot(worldFeet.x - pet.position.x, worldFeet.y - pet.position.y) < 1.01)
    if frame.position.y < actor.corner.y {
      #expect(frame.edge == .right)
      #expect(abs(frame.position.x - hanging.x) < 0.01)
    }
    if (0.14...0.22).contains(progress) {
      let hands = motion.handPoints(at: progress).map {
        CGPoint(
          x: frame.position.x + (AttachmentPose.standing.anchor.x - $0.x) * scale,
          y: frame.position.y + ($0.y - AttachmentPose.standing.anchor.y) * scale)
      }
      #expect(hands.allSatisfy { $0.x < actor.exteriorEdgeX && $0.y >= actor.corner.y })
      if planted.isEmpty { planted = hands }
      for (hand, anchor) in zip(hands, planted) {
        #expect(hypot(hand.x - anchor.x, hand.y - anchor.y) < 0.01)
      }
    }
    previous = frame.position
  }
  #expect(previous == hanging)
  #expect(pet.attachmentPose == .hangingRight)
  #expect(pet.view.rig.hangingArms.opacity == 1)
  for boundary in [start, start + duration] {
    let before = try #require(session.frames(at: boundary - 0.0001).first)
    let after = try #require(session.frames(at: boundary + 0.0001).first)
    #expect(
      hypot(before.position.x - after.position.x, before.position.y - after.position.y) < 0.01)
  }
}
