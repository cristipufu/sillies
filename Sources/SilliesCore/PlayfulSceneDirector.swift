import CoreGraphics
import Foundation

public struct PlayfulSceneDirector: Sendable {
  private static let minimumInterval: Double = 90
  private static let intervalVariation: Double = 90
  private static let retryInterval: Double = 15
  private static let historyLimit = 4
  private var random: SeededRandom
  private var cooldowns: [String: Double] = [:]
  private var recentScenes: [String] = []
  private var lastCast: Set<String> = []
  public private(set) var nextOpportunity: Double?

  public init(seed: UInt64) { random = SeededRandom(seed: seed) }

  public mutating func resume(at time: Double) {
    if nextOpportunity == nil { schedule(after: time) }
  }

  public mutating func suspend() { nextOpportunity = nil }

  public struct Opportunity: Sendable {
    public let time: Double
    public let trigger: PlayfulSceneDefinition.Trigger
    public let participants: [PlayfulSceneParticipant]
    public let window: CGRect?
    public let visibleFrame: CGRect
    public let occupiedFrames: [CGRect]

    public init(
      time: Double, trigger: PlayfulSceneDefinition.Trigger,
      participants: [PlayfulSceneParticipant], window: CGRect?, visibleFrame: CGRect,
      occupiedFrames: [CGRect] = []
    ) {
      self.time = time
      self.trigger = trigger
      self.participants = participants
      self.window = window
      self.visibleFrame = visibleFrame
      self.occupiedFrames = occupiedFrames
    }
  }

  public mutating func select(
    from definitions: [PlayfulSceneDefinition],
    opportunity: Opportunity
  ) -> PlayfulScenePlan? {
    guard let due = nextOpportunity, opportunity.time >= due else { return nil }
    nextOpportunity = opportunity.time + Self.retryInterval
    var candidates = definitions.filter {
      $0.trigger == opportunity.trigger && (cooldowns[$0.id] ?? -.infinity) <= opportunity.time
    }
    let unseen = candidates.filter { !recentScenes.contains($0.id) }
    if !unseen.isEmpty { candidates = unseen }
    while !candidates.isEmpty {
      var draw = random.unit() * candidates.reduce(0) { $0 + $1.weight }
      let index =
        candidates.firstIndex {
          draw -= $0.weight
          return draw <= 0
        } ?? 0
      let definition = candidates.remove(at: index)
      if let plan = makePlan(definition, opportunity: opportunity) {
        didStart(plan, at: opportunity.time)
        return plan
      }
    }
    return nil
  }

  public mutating func makePlan(
    _ definition: PlayfulSceneDefinition,
    opportunity: Opportunity
  ) -> PlayfulScenePlan? {
    let eligible = opportunity.participants.filter { $0.profile.scenes.contains(definition.id) }
      .sorted { $0.position.x < $1.position.x }
    guard eligible.count >= definition.participants else { return nil }
    let start = Int(random.unit() * Double(eligible.count))
    let indices = (0..<eligible.count).map { ($0 + start) % eligible.count }.sorted {
      !lastCast.contains(eligible[$0].id) && lastCast.contains(eligible[$1].id)
    }
    for index in indices where index + definition.participants <= eligible.count {
      let cast = Array(eligible[index..<(index + definition.participants)])
      let ids = Set(cast.map(\.id))
      let messages =
        definition.phases.contains(where: { $0.prop == .sign })
        ? (cast.first?.profile.signs.isEmpty == false ? cast[0].profile.signs : definition.messages)
        : definition.messages
      let message = messages.isEmpty ? "" : messages[Int(random.unit() * Double(messages.count))]
      if let plan = PlayfulSceneLayout.plan(
        .init(
          definition: definition, participants: cast,
          bystanders: opportunity.participants.filter { !ids.contains($0.id) },
          window: opportunity.window, visibleFrame: opportunity.visibleFrame, message: message,
          occupiedFrames: opportunity.occupiedFrames))
      {
        return plan
      }
    }
    return nil
  }

  public mutating func didStart(_ plan: PlayfulScenePlan, at time: Double) {
    cooldowns[plan.definition.id] = time + plan.definition.cooldown
    recentScenes.append(plan.definition.id)
    if recentScenes.count > Self.historyLimit { recentScenes.removeFirst() }
    lastCast = Set(plan.actors.map { $0.participant.id })
    schedule(after: time + plan.definition.duration)
  }

  private mutating func schedule(after time: Double) {
    nextOpportunity = time + Self.minimumInterval + random.unit() * Self.intervalVariation
  }
}
