import Foundation

public struct BehaviorState: Equatable, Sendable {
  public let animation: AnimationID
  public let motion: ReactionMotion
  public let priority: Int
  public let expiresAt: TimeInterval
  public let reactionID: String

  public init(
    animation: AnimationID = .idle, motion: ReactionMotion = .none,
    priority: Int = -1, expiresAt: TimeInterval = 0, reactionID: String = "rest"
  ) {
    self.animation = animation
    self.motion = motion
    self.priority = priority
    self.expiresAt = expiresAt
    self.reactionID = reactionID
  }
}

/// Pure, deterministic behavior selection. No timers, UI objects, or platform APIs.
public struct BehaviorEngine: Sendable {
  private static let minimumActivityMultiplier: Double = 0.35
  private static let defaultIdleSleepDuration: TimeInterval = 20
  private static let fallbackRestDuration: TimeInterval = 3

  public let character: CharacterDefinition
  public private(set) var state = BehaviorState()
  private var cooldowns: [String: TimeInterval] = [:]
  private var random: SeededRandom

  public init(character: CharacterDefinition, seed: UInt64) {
    self.character = character
    random = SeededRandom(seed: seed)
  }

  @discardableResult
  public mutating func receive(_ event: WorkspaceEvent, activity: Double = 1) -> BehaviorState? {
    let candidates = character.reactions.filter {
      $0.event == event.kind && (cooldowns[$0.id] ?? -.infinity) <= event.timestamp
        && (state.expiresAt <= event.timestamp || $0.priority >= state.priority)
    }
    guard let priority = candidates.map(\.priority).max() else { return nil }
    let eligible = candidates.filter { $0.priority == priority }
    let total = eligible.reduce(0) { $0 + $1.weight }
    var draw = random.unit() * total
    let selected =
      eligible.first { reaction in
        draw -= reaction.weight
        return draw <= 0
      } ?? eligible[eligible.count - 1]
    let ambient = event.kind == .ambient || event.kind.rawValue.hasPrefix("ambient.")
    let duration =
      selected.duration * (ambient ? 1 / max(Self.minimumActivityMultiplier, activity) : 1)
    state = BehaviorState(
      animation: selected.animation, motion: selected.motion,
      priority: selected.priority, expiresAt: event.timestamp + duration,
      reactionID: selected.id)
    cooldowns[selected.id] = event.timestamp + selected.cooldown
    return state
  }

  @discardableResult
  public mutating func advance(
    at time: TimeInterval, activity: Double = 1, isIdle: Bool = false,
    ambientEvent: EventKind = .ambient
  )
    -> BehaviorState?
  {
    guard time >= state.expiresAt else { return nil }
    if isIdle {
      if let next = receive(WorkspaceEvent(.userIdle, at: time), activity: activity) { return next }
      state = BehaviorState(
        animation: .sleep, expiresAt: time + Self.defaultIdleSleepDuration, reactionID: "sleep")
    } else {
      if let next = receive(WorkspaceEvent(ambientEvent, at: time), activity: activity) {
        return next
      }
      if ambientEvent != .ambient,
        let fallback = receive(WorkspaceEvent(.ambient, at: time), activity: activity)
      {
        return fallback
      }
      state = BehaviorState(expiresAt: time + Self.fallbackRestDuration)
    }
    return state
  }

  public mutating func reset() {
    state = BehaviorState()
    cooldowns.removeAll(keepingCapacity: true)
  }
}

public struct SeededRandom: Sendable {
  private static let nonZeroFallbackSeed: UInt64 = 0xA076_1D64_78BD_642F
  private static let multiplier: UInt64 = 0x2545_F491_4F6C_DD1D
  private static let mantissaDivisor: Double = 9_007_199_254_740_992

  private var state: UInt64
  public init(seed: UInt64) { state = seed == 0 ? Self.nonZeroFallbackSeed : seed }
  public mutating func unit() -> Double {
    state ^= state >> 12
    state ^= state << 25
    state ^= state >> 27
    return Double((state &* Self.multiplier) >> 11) / Self.mantissaDivisor
  }
}
