import Foundation
import Testing

@testable import SilliesCore

@Test func oldPacksDecodeWithDefaultEntryAndExitTransitions() throws {
  let json = """
    {"schemaVersion":1,"id":"old","name":"Old","subtitle":"","bio":"",
     "renderer":"cat","accent":"AABBCC","speed":20,
     "reactions":[{"id":"rest","event":"ambient","animation":"idle","duration":5,
     "priority":0,"cooldown":0,"weight":1,"motion":"none"}]}
    """
  let character = try JSONDecoder().decode(CharacterDefinition.self, from: Data(json.utf8))
  try character.validate()
  #expect(character.presentationTransitions.definition(for: .enter).animation == .appear)
  #expect(character.presentationTransitions.definition(for: .exit).animation == .disappear)
}

@Test func partialOverridesInheritEntryForReattachmentAndDefaultExit() throws {
  let json = """
    {"enter":{"animation":"ninja.arrive","duration":0.25}}
    """
  let profile = try JSONDecoder().decode(CharacterTransitions.self, from: Data(json.utf8))
  try profile.validate(characterID: "new")
  #expect(profile.definition(for: .reattach) == profile.definition(for: .enter))
  #expect(profile.definition(for: .exit).animation == .disappear)
  let decoded = try JSONDecoder().decode(
    CharacterTransitions.self, from: JSONEncoder().encode(profile))
  #expect(decoded == profile)
}

@Test func transitionDurationsAreBoundedAndFinite() {
  for duration in [-1.0, 0, 3, .infinity, .nan] {
    let profile = CharacterTransitions(
      exit: TransitionDefinition(animation: .disappear, duration: duration))
    #expect(throws: CharacterDefinition.ValidationError.self) {
      try profile.validate(characterID: "bad")
    }
  }
}
