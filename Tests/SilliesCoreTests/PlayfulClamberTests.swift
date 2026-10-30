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
