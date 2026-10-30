import CoreGraphics
import Foundation
import Testing

@testable import SilliesCore

@Test func playfulGlidingPanelKeepsItsLocalRigSteadyAndStaysOutsideTheWindow() {
  let window = CGRect(x: 200, y: 180, width: 760, height: 480)
  let body = CGPoint(x: window.maxX + 64 * 0.8, y: window.midY)
  let first = CompanionWindowLayout.exteriorScene(
    bodyPosition: body, pose: .standing, size: 64, window: window)
  let second = CompanionWindowLayout.exteriorScene(
    bodyPosition: CGPoint(x: body.x + 30, y: body.y - 15), pose: .standing, size: 64, window: window
  )
  #expect(first.contactOffset == second.contactOffset)
  #expect(first.frame.size == second.frame.size)
  #expect(second.frame.minX - first.frame.minX == 30)
  #expect(!first.frame.intersects(window) && !second.frame.intersects(window))
}

private enum SceneFixture {
  static let screen = CGRect(x: 0, y: 0, width: 1440, height: 1000)
  static let window = CGRect(x: 200, y: 180, width: 760, height: 480)
  static let surface = PerchSurface(window: window, visibleFrame: screen, characterSize: 64)
  static let definition = PlayfulSceneDefinition(
    id: "dance", title: "Dance", trigger: .ambient,
    layout: .perches, participants: 2, cooldown: 400, weight: 1, clearanceAbove: 1.4, messages: [],
    phases: [
      .init(
        duration: 2,
        cues: [
          .init(role: .lead, animation: "dance", destination: .home),
          .init(role: .partner, animation: "dance", destination: .home),
        ], prop: .none),
      .init(
        duration: 1,
        cues: [
          .init(role: .lead, animation: .happy, destination: .home),
          .init(role: .partner, animation: .happy, destination: .home),
        ], prop: .none),
    ])
  static func participant(_ id: String, fraction: Double) -> PlayfulSceneParticipant {
    .init(
      id: id, profile: .init(scenes: ["dance"], clips: [:], signs: []), surface: surface,
      position: surface.point(at: fraction), windowID: 42)
  }
  static let cast = [participant("one", fraction: 0.3), participant("two", fraction: 0.7)]
  static func opportunity(at time: Double) -> PlayfulSceneDirector.Opportunity {
    .init(time: time, trigger: .ambient, participants: cast, window: window, visibleFrame: screen)
  }
}

@Test func playfulSceneTimelineSharesPhaseBoundariesAndCancellation() throws {
  let plan = try #require(
    PlayfulSceneLayout.plan(
      .init(
        definition: SceneFixture.definition,
        participants: SceneFixture.cast, bystanders: [], window: SceneFixture.window,
        visibleFrame: SceneFixture.screen, message: "")))
  var session = PlayfulSceneSession(plan: plan, at: 100)
  #expect(session.frames(at: 99).isEmpty)
  #expect(session.frames(at: 101.99).allSatisfy { $0.animation == "dance" })
  #expect(session.frames(at: 102).allSatisfy { $0.animation == .happy })
  #expect(session.frames(at: 103).isEmpty)
  session.cancel()
  session.cancel()
  #expect(session.frames(at: 101).isEmpty)
}

@Test func playfulScenesRespectCooldownAndResumeWithoutAnImmediateBurst() throws {
  var director = PlayfulSceneDirector(seed: 7)
  director.resume(at: 0)
  #expect(
    director.select(from: [SceneFixture.definition], opportunity: SceneFixture.opportunity(at: 0))
      == nil)
  let due = try #require(director.nextOpportunity)
  #expect((90...180).contains(due))
  #expect(
    director.select(from: [SceneFixture.definition], opportunity: SceneFixture.opportunity(at: due))
      != nil)
  let next = try #require(director.nextOpportunity)
  #expect(
    director.select(
      from: [SceneFixture.definition], opportunity: SceneFixture.opportunity(at: next)) == nil)
  director.suspend()
  #expect(director.nextOpportunity == nil)
  director.resume(at: 5000)
  #expect(try #require(director.nextOpportunity) >= 5090)
}

@Test func playfulScenesRejectCrowdedStagesAndDifferentWindows() {
  let request = PlayfulSceneLayout.Request(
    definition: SceneFixture.definition,
    participants: SceneFixture.cast, bystanders: [SceneFixture.participant("three", fraction: 0.5)],
    window: SceneFixture.window, visibleFrame: SceneFixture.screen, message: "")
  #expect(PlayfulSceneLayout.plan(request) == nil)
  let other = SceneFixture.cast[1]
  let foreign = PlayfulSceneParticipant(
    id: other.id, profile: other.profile, surface: other.surface,
    position: other.position, windowID: 99)
  #expect(
    PlayfulSceneLayout.plan(
      .init(
        definition: SceneFixture.definition,
        participants: [SceneFixture.cast[0], foreign], bystanders: [], window: SceneFixture.window,
        visibleFrame: SceneFixture.screen, message: "")) == nil)
}

@Test func playfulSceneAvoidsBusyCompanionsThatCannotJoinTheCast() {
  let occupied = CGRect(
    x: SceneFixture.surface.point(at: 0.5).x - 32,
    y: SceneFixture.surface.point(at: 0.5).y, width: 64, height: 90)
  var director = PlayfulSceneDirector(seed: 7)
  let opportunity = PlayfulSceneDirector.Opportunity(
    time: 0, trigger: .ambient, participants: SceneFixture.cast,
    window: SceneFixture.window, visibleFrame: SceneFixture.screen, occupiedFrames: [occupied])
  #expect(director.makePlan(SceneFixture.definition, opportunity: opportunity) == nil)
}

@Test(arguments: [48.0, 64, 112])
func playfulScenePlanningSupportsSizesAndNegativeScreenOrigins(size: Double) throws {
  let screen = SceneFixture.screen.offsetBy(dx: -1600, dy: 900)
  let window = SceneFixture.window.offsetBy(dx: -1600, dy: 900)
  let surface = PerchSurface(window: window, visibleFrame: screen, characterSize: size)
  let cast = SceneFixture.cast.enumerated().map { index, actor in
    PlayfulSceneParticipant(
      id: actor.id, profile: actor.profile, surface: surface,
      position: surface.point(at: index == 0 ? 0.3 : 0.7), windowID: actor.windowID)
  }
  let plan = try #require(
    PlayfulSceneLayout.plan(
      .init(
        definition: SceneFixture.definition, participants: cast, bystanders: [],
        window: window, visibleFrame: screen, message: "")))
  #expect(plan.actors.allSatisfy { screen.contains($0.stage) })
  let grip = AttachmentPose.hangingRight.contactOffset(from: .standing, size: size)
  for actor in plan.actors {
    for destination: PlayfulSceneDefinition.Destination in [.outside, .below] {
      let body = actor.point(for: destination, pose: .hangingRight)
      let bounds = CompanionWindowLayout.exteriorScene(
        bodyPosition: body, pose: .hangingRight, size: size, window: window)
      #expect(abs(body.x + grip.x - window.maxX) < 0.01)
      #expect(!bounds.frame.intersects(window))
      #expect(abs(bounds.contactOffset.x) < 0.01)
    }
    let pullUp = PlayfulClamberMotion(actor: actor)
    var previousX = pullUp.position(at: 0).x
    for sample in 0...100 {
      let progress = Double(sample) / 100
      let body = pullUp.position(at: progress)
      #expect(body.x <= previousX)
      if pullUp.edge(at: progress) == .top {
        #expect(body.y >= window.maxY)
      } else {
        #expect(body.x >= window.maxX)
      }
      previousX = body.x
    }
    #expect(pullUp.position(at: 1) == actor.corner)
  }
  let crampedScreen = CGRect(
    x: screen.minX, y: screen.minY, width: screen.width,
    height: window.maxY - screen.minY + size)
  #expect(
    PlayfulSceneLayout.plan(
      .init(
        definition: SceneFixture.definition, participants: cast, bystanders: [],
        window: window, visibleFrame: crampedScreen, message: "")) == nil)
}

@Test(arguments: [48.0, 64, 112])
func playfulPlaneTravelsFarWithoutAnOversizedPanel(size: Double) {
  let visible = SceneFixture.screen.offsetBy(dx: -1600, dy: 900)
  for x in [visible.minX + 60, visible.midX, visible.maxX - 60] {
    let origin = CGPoint(x: x, y: visible.minY + 500)
    let launch = PlayfulPlaneFlight.frame(origin: origin, size: size, visible: visible, progress: 0)
    let landing = PlayfulPlaneFlight.frame(
      origin: origin, size: size, visible: visible, progress: 1)
    #expect(abs(landing.midX - launch.midX) >= 450)
    for sample in 0...100 {
      let frame = PlayfulPlaneFlight.frame(
        origin: origin, size: size, visible: visible, progress: Double(sample) / 100)
      #expect(visible.contains(frame))
      #expect(frame.size == PlayfulPlaneFlight.panelSize)
      #expect(frame.minY >= origin.y)
    }
  }
}
