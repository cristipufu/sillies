import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func playfulTugTravelsInBothDirectionsWithoutSeparatingTheCast() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("tug-of-war")
  let session = PlayfulSceneSession(plan: plan, at: 0)
  let index = try #require(plan.definition.phases.firstIndex { $0.prop == .rope })
  let phase = plan.definition.phases[index]
  var offsets: [Double] = []
  for sample in 0..<100 {
    let frames = session.frames(
      at: session.phaseStart(index) + phase.duration * Double(sample) / 100)
    let lead = try #require(frames.first { $0.actor.role == .lead })
    let partner = try #require(frames.first { $0.actor.role == .partner })
    let offset = lead.position.x - lead.actor.stage.x
    offsets.append(offset)
    #expect(abs(partner.position.x - partner.actor.stage.x - offset) < 0.01)
    let rope = try #require(
      PlayfulPropLayout.frame(
        for: .init(
          prop: .rope, frames: frames, plan: plan, textSize: .zero)))
    #expect(abs(rope.midX - (lead.position.x + partner.position.x) / 2) < 0.01)
  }
  #expect(try #require(offsets.max()) > 15)
  #expect(try #require(offsets.min()) < -15)
}

@Test @MainActor func playfulParachuteGlidesAndBanksWithinTheExteriorRoute() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("parachute")
  let session = PlayfulSceneSession(plan: plan, at: 0)
  let index = try #require(plan.definition.phases.firstIndex { $0.prop == .parachute })
  let phase = plan.definition.phases[index]
  let motion = try #require(phase.motion)
  var positions: [Double] = []
  var angles: [Double] = []
  for sample in 0..<100 {
    let progress = Double(sample) / 100
    let frames = session.frames(at: session.phaseStart(index) + phase.duration * progress)
    positions.append(try #require(frames.first).position.x)
    angles.append(motion.bankAngle(at: progress))
    let canopy = try #require(
      PlayfulPropLayout.frame(
        for: .init(
          prop: .parachute, frames: frames, plan: plan, textSize: .zero)))
    #expect(!canopy.intersects(fixture.window))
    #expect(fixture.visible.contains(canopy))
  }
  #expect(try #require(positions.max()) - #require(positions.min()) > 25)
  #expect(try #require(angles.max()) > 0.08)
  #expect(try #require(angles.min()) < -0.08)
}

@Test @MainActor func playfulPlaneNoteReturnsToTheMascot() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("paper-plane")
  let session = PlayfulSceneSession(plan: plan, at: 0)
  let index = try #require(plan.definition.phases.firstIndex { $0.prop == .letter })
  let frames = session.frames(at: session.phaseStart(index))
  let actor = try #require(frames.first)
  let bubble = try #require(
    PlayfulPropLayout.frame(
      for: .init(
        prop: .letter, frames: frames, plan: plan, textSize: CGSize(width: 180, height: 70))))
  #expect(abs(bubble.midX - actor.position.x) < 0.01)
}

@Test @MainActor func playfulShoveWaitsForContactAndReturnsThePartnerAlongTheBorder() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("shove")
  let session = PlayfulSceneSession(plan: plan, at: 0)
  let index = try #require(
    plan.definition.phases.firstIndex {
      $0.cues.contains { $0.animation == "scene.shove" }
    })
  let phase = plan.definition.phases[index]
  let cue = try #require(phase.cues.first { $0.role == .partner })
  let contact = session.phaseStart(index) + phase.duration * (cue.movementStart ?? 0)
  let before = session.frames(at: contact - 0.01)
  let pusher = try #require(before.first { $0.actor.role == .lead })
  let victim = try #require(before.first { $0.actor.role == .partner })
  let size = victim.actor.participant.surface.presentationSize
  #expect(victim.position == victim.actor.corner)
  #expect(abs(victim.position.x - pusher.position.x - size * 0.8) < 0.01)
  let moving = try #require(session.frames(at: contact + 0.2).first { $0.actor.role == .partner })
  #expect(moving.position.x > victim.position.x)
  let recovery = try #require(
    plan.definition.phases.firstIndex {
      $0.cues.contains { $0.role == .partner && $0.animation == .climb }
    })
  let frames = session.frames(at: session.phaseStart(recovery) + 0.5)
  let returning = try #require(frames.first { $0.actor.role == .partner })
  #expect(returning.pose == .hangingRight)
  #expect(abs(returning.gripPoint.x - fixture.window.maxX) < 0.01)

}

@Test @MainActor func playfulClamberKeepsNativePlacementContinuousWithoutPropWindows() throws {
  let nativeRoundingTolerance = 1.01
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  for id in ["edge-climb", "shove", "parachute"] {
    let plan = try fixture.plan(id)
    let session = PlayfulSceneSession(plan: plan, at: 0)
    let index = try #require(
      plan.definition.phases.firstIndex {
        $0.cues.contains { $0.animation == "scene.clamber" }
      })
    let boundary = session.phaseStart(index)
    let phase = plan.definition.phases[index]
    let role = try #require(phase.cues.first { $0.animation == "scene.clamber" }).role
    let before = try #require(
      session.frames(at: boundary - 0.0001).first {
        $0.actor.role == role
      })
    let after = try #require(
      session.frames(at: boundary + 0.0001).first {
        $0.actor.role == role
      })
    #expect(
      hypot(before.position.x - after.position.x, before.position.y - after.position.y) < 0.01)
    #expect(before.facingRight == after.facingRight)
    try fixture.start(id)
    fixture.coordinator.advance(at: boundary - 0.0001)
    let climber = try #require(fixture.companions.first { $0.attachmentPose == .hangingRight })
    let nativeBefore = climber.panel.frame
    fixture.coordinator.advance(at: boundary + 0.0001)
    #expect(climber.panel.frame.size == nativeBefore.size)
    #expect(abs(climber.panel.frame.minY - nativeBefore.minY) < 0.01)
    for sample in 0...100 {
      let progress = Double(sample) / 100
      fixture.coordinator.advance(at: boundary + phase.duration * progress)
      #expect(fixture.coordinator.windowNumbers.isEmpty)
      #expect(!fixture.coordinator.hasVisibleProp)
      #expect(!climber.panel.frame.intersects(fixture.window))
      let localFeet = climber.view.rig.stage.convert(
        AttachmentPose.standing.anchor, to: climber.view.layer)
      let worldFeet = CGPoint(
        x: localFeet.x + climber.panel.frame.minX, y: localFeet.y + climber.panel.frame.minY)
      #expect(
        hypot(worldFeet.x - climber.position.x, worldFeet.y - climber.position.y)
          < nativeRoundingTolerance)
    }
    fixture.coordinator.advance(at: session.endsAt)
    #expect(fixture.coordinator.windowNumbers.isEmpty)
    #expect(fixture.coordinator.propPreviews.isEmpty)
  }
}

@Test @MainActor func playfulClamberMovesTheHandsOntoTheLedgeBeforeCrossingTheCorner() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("edge-climb")
  let actor = try #require(plan.actors.first)
  let motion = PlayfulClamberMotion(actor: actor)
  let scale = actor.participant.surface.presentationSize / 100
  let standing = AttachmentPose.standing.anchor
  var previous = actor.point(for: .outside, pose: .hangingRight)
  var planted: [CGPoint] = []
  for sample in 0...100 {
    let progress = Double(sample) / 100
    let body = motion.position(at: progress)
    #expect(body.x <= previous.x + 0.01)
    #expect(hypot(body.x - previous.x, body.y - previous.y) < 4)
    if body.x < actor.exteriorEdgeX {
      #expect(body.y >= actor.corner.y)
      #expect(motion.edge(at: progress) == .top)
    }
    let hands = motion.handPoints(at: progress).map {
      CGPoint(x: body.x + (standing.x - $0.x) * scale, y: body.y + ($0.y - standing.y) * scale)
    }
    if (0.78...0.86).contains(progress) {
      #expect(hands.allSatisfy { $0.x < actor.exteriorEdgeX && $0.y >= actor.corner.y })
      if planted.isEmpty { planted = hands }
      for (hand, anchor) in zip(hands, planted) {
        #expect(hypot(hand.x - anchor.x, hand.y - anchor.y) < 0.01)
      }
    }
    previous = body
  }
  #expect(motion.position(at: 1) == actor.corner)
}
