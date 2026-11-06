import Foundation
import Observation
import SilliesCore

/// User overrides are separate from character packs and never change another companion.
@MainActor @Observable final class CompanionPreferences {
  struct Customization: Codable, Equatable, Sendable {
    var language: String?
    var personality: String?
    var voices: [String: String] = [:]
    var textModelID: String?
  }

  private static let key = "companionProfiles"
  private(set) var values: [String: Customization]
  private(set) var error: String?
  @ObservationIgnored var onChange: ((String) -> Void)?
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults, characters: [CharacterDefinition]) {
    self.defaults = defaults
    do {
      var loaded =
        try defaults.data(forKey: Self.key).map {
          try JSONDecoder().decode([String: Customization].self, from: $0)
        } ?? [:]
      for character in characters {
        guard let base = character.chat, let value = loaded[character.id] else { continue }
        do { try Self.applying(value, to: base).validate() } catch {
          loaded.removeValue(forKey: character.id)
          self.error = String(localized: "Companion preferences could not be loaded.")
          fputs("Invalid companion preferences: \(error)\n", stderr)
        }
      }
      values = loaded
    } catch {
      values = [:]
      self.error = String(localized: "Companion preferences could not be loaded.")
      fputs("Companion preferences: \(error)\n", stderr)
    }
  }

  func customization(for id: String) -> Customization { values[id] ?? .init() }

  func profile(for character: CharacterDefinition) -> CharacterChatProfile? {
    guard let base = character.chat else { return nil }
    return Self.applying(customization(for: character.id), to: base)
  }

  private static func applying(_ custom: Customization, to base: CharacterChatProfile)
    -> CharacterChatProfile
  {
    return .init(
      personality: custom.personality ?? base.personality,
      languageIdentifier: custom.language ?? base.languageIdentifier,
      preferredVoices: base.preferredVoices.merging(custom.voices) { _, new in new })
  }

  func save(_ value: Customization, for character: CharacterDefinition) {
    guard let base = character.chat else { return }
    do {
      try Self.applying(value, to: base).validate()
      var updated = values
      updated[character.id] = value
      let data = try JSONEncoder().encode(updated)
      defaults.set(data, forKey: Self.key)
      values = updated
      error = nil
      onChange?(character.id)
    } catch {
      self.error = String(localized: "These companion preferences could not be saved.")
      fputs("Companion preferences: \(error)\n", stderr)
    }
  }

  func reset(_ character: CharacterDefinition) { save(.init(), for: character) }
}
