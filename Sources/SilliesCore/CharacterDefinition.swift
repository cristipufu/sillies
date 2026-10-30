import Foundation

public enum ReactionMotion: String, Codable, Sendable {
  case none, stroll, hop
}

public struct ReactionDefinition: Codable, Sendable, Equatable {
  public let id: String
  public let event: EventKind
  public let animation: AnimationID
  public let duration: Double
  public let priority: Int
  public let cooldown: Double
  public let weight: Double
  public let motion: ReactionMotion

  public init(
    id: String, event: EventKind, animation: AnimationID, duration: Double,
    priority: Int = 0, cooldown: Double = 0, weight: Double = 1,
    motion: ReactionMotion = .none
  ) {
    self.id = id
    self.event = event
    self.animation = animation
    self.duration = duration
    self.priority = priority
    self.cooldown = cooldown
    self.weight = weight
    self.motion = motion
  }
}

public struct CharacterDefinition: Codable, Sendable, Identifiable {
  public static let supportedSchemaVersion = 1
  public static let maxSpeed: Double = 300
  public static let accentHexLength = 6
  public static let minReactionDuration: Double = 0.15
  public static let maxReactionDuration: Double = 300

  public let schemaVersion: Int
  public let id: String
  public let name: String
  public let subtitle: String
  public let bio: String
  public let renderer: String
  public let accent: String
  public let speed: Double
  public let order: Int?
  public let reactions: [ReactionDefinition]
  public let transitions: CharacterTransitions?
  public let playful: PlayfulCharacterProfile?

  public var presentationTransitions: CharacterTransitions { transitions ?? CharacterTransitions() }

  public init(
    schemaVersion: Int = Self.supportedSchemaVersion, id: String, name: String, subtitle: String,
    bio: String, renderer: String, accent: String, speed: Double, order: Int? = nil,
    reactions: [ReactionDefinition], transitions: CharacterTransitions? = nil,
    playful: PlayfulCharacterProfile? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.subtitle = subtitle
    self.bio = bio
    self.renderer = renderer
    self.accent = accent
    self.speed = speed
    self.order = order
    self.reactions = reactions
    self.transitions = transitions
    self.playful = playful
  }

  public func validate() throws {
    guard schemaVersion == Self.supportedSchemaVersion else {
      throw ValidationError("Unsupported schema version for \(id)")
    }
    guard !id.isEmpty, !name.isEmpty, !renderer.isEmpty else {
      throw ValidationError("Missing character identity")
    }
    guard speed.isFinite, speed > 0, speed <= Self.maxSpeed else {
      throw ValidationError("Invalid speed for \(id)")
    }
    guard accent.count == Self.accentHexLength, UInt32(accent, radix: 16) != nil else {
      throw ValidationError("Invalid accent for \(id)")
    }
    guard Set(reactions.map(\.id)).count == reactions.count else {
      throw ValidationError("Duplicate reaction in \(id)")
    }
    guard reactions.contains(where: { $0.event == .ambient }) else {
      throw ValidationError("\(id) needs an ambient reaction")
    }
    try presentationTransitions.validate(characterID: id)
    try playful?.validate()
    for reaction in reactions {
      guard !reaction.id.isEmpty, !reaction.event.rawValue.isEmpty,
        !reaction.animation.rawValue.isEmpty,
        reaction.duration.isFinite, reaction.duration >= Self.minReactionDuration,
        reaction.duration <= Self.maxReactionDuration,
        reaction.cooldown.isFinite, reaction.cooldown >= 0,
        reaction.weight.isFinite, reaction.weight > 0
      else {
        throw ValidationError("Invalid reaction \(reaction.id) in \(id)")
      }
    }
  }

  public struct ValidationError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
  }
}
