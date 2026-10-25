import Foundation
import SilliesCore

struct CharacterCatalog {
  let characters: [CharacterDefinition]

  @MainActor
  func validateAssets(
    renderers: RendererRegistry, animations: AnimationLibrary, transitions: TransitionLibrary
  ) throws {
    for character in characters {
      guard renderers.contains(character.renderer) else {
        throw CharacterDefinition.ValidationError(
          "Missing renderer '\(character.renderer)' for \(character.name)")
      }
      for reaction in character.reactions {
        for pose in [AttachmentPose.standing, .hangingLeft, .hangingRight]
        where !animations.contains(reaction.animation, characterID: character.id, pose: pose) {
          throw CharacterDefinition.ValidationError(
            "Unknown animation or pose variant '\(reaction.animation.rawValue)' in \(character.name)"
          )
        }
      }
      for kind in TransitionKind.allCases {
        let transition = character.presentationTransitions.definition(for: kind)
        guard transitions.contains(transition.animation) else {
          throw CharacterDefinition.ValidationError(
            "Unknown \(kind.rawValue) transition '\(transition.animation.rawValue)' in \(character.name)"
          )
        }
      }
    }
  }

  init() throws {
    guard
      let folder = Bundle.main.url(forResource: "Characters", withExtension: nil)
        ?? Bundle.module.url(forResource: "Characters", withExtension: nil)
    else {
      throw CharacterDefinition.ValidationError("Missing bundled character catalog")
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let decoded = try files.map { url in
      try JSONDecoder().decode(
        CharacterDefinition.self, from: Data(contentsOf: url))
    }
    try self.init(characters: decoded)
  }

  init(characters: [CharacterDefinition]) throws {
    for character in characters { try character.validate() }
    guard !characters.isEmpty, Set(characters.map(\.id)).count == characters.count else {
      throw CharacterDefinition.ValidationError(
        "Catalog is empty or contains duplicate character IDs")
    }
    self.characters = characters.sorted {
      let lhsOrder = $0.order ?? ($0.id == "mochi" ? 0 : Int.max)
      let rhsOrder = $1.order ?? ($1.id == "mochi" ? 0 : Int.max)
      if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
      return $0.id < $1.id
    }
  }
}
