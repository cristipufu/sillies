import Foundation

public enum TransitionKind: String, Codable, CaseIterable, Sendable {
  case enter, exit, reattach
}

public struct TransitionDefinition: Codable, Equatable, Sendable {
  public let animation: AnimationID
  public let duration: Double

  public init(animation: AnimationID, duration: Double) {
    self.animation = animation
    self.duration = duration
  }
}

/// Optional pack overrides preserve the defaults when older character packs are loaded.
public struct CharacterTransitions: Codable, Equatable, Sendable {
  public let enter: TransitionDefinition?
  public let exit: TransitionDefinition?
  public let reattach: TransitionDefinition?

  public init(
    enter: TransitionDefinition? = nil, exit: TransitionDefinition? = nil,
    reattach: TransitionDefinition? = nil
  ) {
    self.enter = enter
    self.exit = exit
    self.reattach = reattach
  }

  public func definition(for kind: TransitionKind) -> TransitionDefinition {
    switch kind {
    case .enter: enter ?? TransitionDefinition(animation: .appear, duration: 0.3)
    case .exit: exit ?? TransitionDefinition(animation: .disappear, duration: 0.18)
    case .reattach: reattach ?? definition(for: .enter)
    }
  }

  public func validate(characterID: String) throws {
    for kind in TransitionKind.allCases {
      let transition = definition(for: kind)
      guard !transition.animation.rawValue.isEmpty,
        transition.duration.isFinite, transition.duration >= 0.05, transition.duration <= 2
      else {
        throw CharacterDefinition.ValidationError(
          "Invalid \(kind.rawValue) transition in \(characterID)")
      }
    }
  }
}
