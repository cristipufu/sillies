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
    for progress in [0.0, 0.5, 0.99] {
      fixture.coordinator.advance(at: boundary + phase.duration * progress)
      #expect(fixture.coordinator.windowNumbers.isEmpty)
      #expect(!fixture.coordinator.hasVisibleProp)
      #expect(!climber.panel.frame.intersects(fixture.window))
    }
    fixture.coordinator.advance(at: session.endsAt)
    #expect(fixture.coordinator.windowNumbers.isEmpty)
    #expect(fixture.coordinator.propPreviews.isEmpty)
  }
}

@Test @MainActor func playfulClamberKeepsTheHandsPlantedUntilRelease() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let plan = try fixture.plan("edge-climb")
  let actor = try #require(plan.actors.first)
  let scale = actor.participant.surface.presentationSize / 100
  let from = actor.point(for: .outside, pose: .hangingRight)
  let to = actor.point(for: .outside)
  let original = PlayfulClamberGrip.points(actor: actor, progress: 0)
  for sample in 0...68 {
    let progress = Double(sample) / 100
    let eased = progress * progress * (3 - 2 * progress)
    let body = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
    for (grip, start) in zip(PlayfulClamberGrip.points(actor: actor, progress: progress), original)
    {
      let world = CGPoint(x: body.x + (64 - grip.x) * scale, y: body.y + (grip.y - 20) * scale)
      let anchor = CGPoint(x: from.x + (64 - start.x) * scale, y: from.y + (start.y - 20) * scale)
      #expect(hypot(world.x - anchor.x, world.y - anchor.y) < 0.01)
      #expect(abs(world.x - fixture.window.maxX) < 0.01)
    }
  }
}
