import Foundation
import Testing

@testable import SilliesCore

@Test func wallContextSelectsClimbingWithoutCharacterSpecificEngineCode() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(
        id: "climb", event: .ambientWall, animation: .climb, duration: 5, motion: .stroll)
    ]), seed: 1)
  let state = engine.advance(at: 0, activity: 0.5, ambientEvent: .ambientWall)
  #expect(state?.animation == .climb)
  #expect(state?.motion == .stroll)
  #expect(state?.expiresAt == 10)
}

@Test func charactersWithoutWallOverridesKeepTheirNormalAmbientBehavior() {
  var engine = BehaviorEngine(character: character([]), seed: 1)
  #expect(engine.advance(at: 0, ambientEvent: .ambientWall)?.animation == .idle)
}

private func character(_ reactions: [ReactionDefinition]) -> CharacterDefinition {
  CharacterDefinition(
    id: "test", name: "Test", subtitle: "", bio: "", renderer: "test", accent: "AABBCC", speed: 30,
    reactions: [ReactionDefinition(id: "rest", event: .ambient, animation: .idle, duration: 5)]
      + reactions)
}

@Test func eventRoutesOnlyMatchingReactions() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(id: "pet", event: .pet, animation: .happy, duration: 2, priority: 3),
      ReactionDefinition(
        id: "move", event: .windowMoved, animation: .balance, duration: 1, priority: 2),
    ]), seed: 1)
  #expect(engine.receive(WorkspaceEvent(.scroll, at: 10)) == nil)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 10))?.animation == .happy)
}

@Test func highPriorityReactionCannotBeInterruptedByAmbientActivity() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(
        id: "picked-up", event: .pickedUp, animation: .surprised, duration: 2, priority: 6),
      ReactionDefinition(
        id: "move", event: .windowMoved, animation: .balance, duration: 1, priority: 2),
    ]), seed: 1)
  engine.receive(WorkspaceEvent(.pickedUp, at: 10))
  #expect(engine.receive(WorkspaceEvent(.ambient, at: 10.1)) == nil)
  #expect(engine.receive(WorkspaceEvent(.windowMoved, at: 10.2)) == nil)
  #expect(engine.state.animation == .surprised)
  #expect(engine.receive(WorkspaceEvent(.windowMoved, at: 12))?.animation == .balance)
}

@Test func reactionCooldownSurvivesStateExpiration() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(
        id: "greet", event: .pet, animation: .happy, duration: 1, priority: 2, cooldown: 10)
    ]), seed: 1)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 10)) != nil)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 12)) == nil)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 20)) != nil)
}

@Test func reactionsChooseHighestEligiblePriority() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(
        id: "small", event: .pet, animation: .wave, duration: 1, priority: 1, weight: 100),
      ReactionDefinition(
        id: "big", event: .pet, animation: .happy, duration: 1, priority: 3, weight: 1),
    ]), seed: 4)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 1))?.reactionID == "big")
}

@Test func noAmbientCandidateStillProducesFutureDeadline() {
  let definition = CharacterDefinition(
    id: "test", name: "Test", subtitle: "", bio: "", renderer: "test", accent: "AABBCC", speed: 30,
    reactions: [
      ReactionDefinition(id: "rest", event: .ambient, animation: .idle, duration: 1, cooldown: 50)
    ])
  var engine = BehaviorEngine(character: definition, seed: 1)
  engine.advance(at: 0)
  let fallback = engine.advance(at: 1)
  #expect(fallback?.animation == .idle)
  #expect(fallback!.expiresAt > 1)
}

@Test func idleCharactersSleepAndWakeOnReturn() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(
        id: "return", event: .userReturned, animation: .wave, duration: 2, priority: 2)
    ]), seed: 1)
  #expect(engine.advance(at: 1, isIdle: true)?.animation == .sleep)
  #expect(engine.receive(WorkspaceEvent(.userReturned, at: 2))?.animation == .wave)
}

@Test func sameSeedProducesSameWeightedSequence() {
  let definition = character([
    ReactionDefinition(id: "walk", event: .ambient, animation: .walk, duration: 3, weight: 3)
  ])
  var first = BehaviorEngine(character: definition, seed: 42)
  var second = BehaviorEngine(character: definition, seed: 42)
  var sequence: [AnimationID] = []
  for time in stride(from: 0.0, to: 200, by: 10) {
    let a = first.advance(at: time)
    let b = second.advance(at: time)
    #expect(a == b)
    sequence.append(a!.animation)
  }
  #expect(Set(sequence).count == 2)
}

@Test func calmModeExtendsAmbientRestWithoutSlowingReactions() {
  var engine = BehaviorEngine(
    character: character([
      ReactionDefinition(id: "pet", event: .pet, animation: .happy, duration: 2, priority: 2)
    ]), seed: 1)
  #expect(engine.advance(at: 10, activity: 0.5)?.expiresAt == 20)
  #expect(engine.receive(WorkspaceEvent(.pet, at: 11), activity: 0.5)?.expiresAt == 13)
}

@Test func customEventAndAnimationIdentifiersRoundTrip() throws {
  let reaction = ReactionDefinition(
    id: "build", event: "buildFinished", animation: "victoryDance", duration: 3)
  let decoded = try JSONDecoder().decode(
    ReactionDefinition.self, from: JSONEncoder().encode(reaction))
  #expect(decoded == reaction)
}

@Test func bundledCharacterPacksAreValidAndDistinct() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  let folder = root.appendingPathComponent("Sources/SilliesApp/Resources/Characters")
  let urls = try FileManager.default.contentsOfDirectory(
    at: folder, includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "json" }
  let definitions = try urls.map {
    try JSONDecoder().decode(CharacterDefinition.self, from: Data(contentsOf: $0))
  }
  #expect(definitions.count >= 2)
  #expect(Set(definitions.map(\.id)).count == definitions.count)
  #expect(Set(definitions.map(\.renderer)).count == definitions.count)
  for definition in definitions {
    try definition.validate()
    for event: EventKind in [
      .appChanged, .windowMoved, .windowResized, .windowDisappeared, .pet, .userIdle,
      .userReturned, .edgeReached,
    ] {
      #expect(definition.reactions.contains { $0.event == event })
    }
  }
}

@Test func invalidPacksFailBeforeRendering() {
  let bad = character([
    ReactionDefinition(id: "broken", event: .pet, animation: .happy, duration: -1)
  ])
  #expect(throws: CharacterDefinition.ValidationError.self) { try bad.validate() }
  let duplicate = character([
    ReactionDefinition(id: "rest", event: .pet, animation: .happy, duration: 1)
  ])
  #expect(throws: CharacterDefinition.ValidationError.self) { try duplicate.validate() }
}
