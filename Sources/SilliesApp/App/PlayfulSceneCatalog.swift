import Foundation
import SilliesCore

struct PlayfulSceneCatalog {
  let scenes: [PlayfulSceneDefinition]

  init() throws {
    guard
      let url = Bundle.main.url(
        forResource: "playful-scenes", withExtension: "json", subdirectory: "Scenes")
        ?? Bundle.module.url(
          forResource: "playful-scenes", withExtension: "json", subdirectory: "Scenes")
    else { throw CharacterDefinition.ValidationError("Missing playful scene catalog") }
    try self.init(
      scenes: JSONDecoder().decode([PlayfulSceneDefinition].self, from: Data(contentsOf: url)))
  }

  init(scenes: [PlayfulSceneDefinition]) throws {
    guard !scenes.isEmpty, Set(scenes.map(\.id)).count == scenes.count else {
      throw CharacterDefinition.ValidationError("Empty or duplicate playful scene catalog")
    }
    for scene in scenes { try scene.validate() }
    self.scenes = scenes
  }

  @MainActor
  func validate(characters: CharacterCatalog, animations: AnimationLibrary) throws {
    let ids = Set(scenes.map(\.id))
    for character in characters.characters {
      guard let profile = character.playful else { continue }
      guard Set(profile.scenes).isSubset(of: ids) else {
        throw CharacterDefinition.ValidationError("Unknown playful scene in \(character.id)")
      }
      for scene in scenes where profile.scenes.contains(scene.id) {
        for cue in scene.phases.flatMap(\.cues) {
          guard
            animations.contains(
              profile.animation(for: cue.animation), characterID: character.id,
              pose: cue.pose ?? .standing)
          else {
            throw CharacterDefinition.ValidationError(
              "Missing playful clip in \(character.id): \(cue.animation.rawValue)")
          }
        }
      }
    }
  }
}
