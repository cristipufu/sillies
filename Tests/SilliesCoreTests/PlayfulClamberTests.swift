import Foundation
import Testing

@testable import SilliesCore

@Test func playfulCornerTravelRequiresACompatibleGripAndLanding() throws {
  let hanging = PlayfulSceneDefinition.Cue(
    role: .lead, animation: .hang, destination: .outside,
    staging: .init(pose: .hangingRight))
  let standing = PlayfulSceneDefinition.Cue(role: .lead, animation: .idle, destination: .outside)
  let pullUp = PlayfulSceneDefinition.Cue.Staging(facing: .left, travel: .cornerPullUp)
  let landing = PlayfulSceneDefinition.Cue(
    role: .lead, animation: "scene.clamber", destination: .corner, staging: pullUp)
  let valid = cornerScene(approach: hanging, landing: landing)
  try valid.validate()
  let decoded = try JSONDecoder().decode(
    PlayfulSceneDefinition.self, from: JSONEncoder().encode(valid))
  #expect(decoded == valid)
  #expect(throws: CharacterDefinition.ValidationError.self) {
    try cornerScene(approach: standing, landing: landing).validate()
  }
  let unsafeLanding = PlayfulSceneDefinition.Cue(
    role: .lead, animation: "scene.clamber", destination: .below, staging: pullUp)
  #expect(throws: CharacterDefinition.ValidationError.self) {
    try cornerScene(approach: hanging, landing: unsafeLanding).validate()
  }
}

private func cornerScene(
  approach: PlayfulSceneDefinition.Cue, landing: PlayfulSceneDefinition.Cue
) -> PlayfulSceneDefinition {
  PlayfulSceneDefinition(
    id: "corner", title: "Corner", trigger: .ambient, layout: .exterior,
    participants: 1, cooldown: 100, weight: 1, clearanceAbove: 1.5, messages: [],
    phases: [
      .init(duration: 1, cues: [approach], prop: .none),
      .init(duration: 1, cues: [landing], prop: .none),
      .init(
        duration: 1, cues: [.init(role: .lead, animation: .idle, destination: .home)], prop: .none),
    ])
}

@Test func playfulCornerLoweringRequiresALedgeAndFinishesOnTheBorder() throws {
  let approach = PlayfulSceneDefinition.Cue(role: .lead, animation: .walk, destination: .corner)
  let lowering = PlayfulSceneDefinition.Cue(
    role: .lead, animation: "scene.lower", destination: .outside,
    staging: .init(pose: .hangingRight, facing: .left, travel: .cornerLowering))
  let valid = cornerScene(approach: approach, landing: lowering)
  try valid.validate()
  #expect(
    try JSONDecoder().decode(PlayfulSceneDefinition.self, from: JSONEncoder().encode(valid))
      == valid)
  let airborne = PlayfulSceneDefinition.Cue(role: .lead, animation: .walk, destination: .outside)
  #expect(throws: CharacterDefinition.ValidationError.self) {
    try cornerScene(approach: airborne, landing: lowering).validate()
  }
  for staging in [
    PlayfulSceneDefinition.Cue.Staging(facing: .left, travel: .cornerLowering),
    .init(pose: .hangingRight, facing: .right, travel: .cornerLowering),
    .init(pose: .hangingRight, facing: .left, movementStart: 0.2, travel: .cornerLowering),
  ] {
    let unsupported = PlayfulSceneDefinition.Cue(
      role: .lead, animation: "scene.lower", destination: .outside, staging: staging)
    #expect(throws: CharacterDefinition.ValidationError.self) {
      try cornerScene(approach: approach, landing: unsupported).validate()
    }
  }
}
