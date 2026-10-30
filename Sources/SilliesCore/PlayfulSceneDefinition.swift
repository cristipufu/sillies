import Foundation

/// Bundled choreography contains choices and timing; it never executes platform code.
public struct PlayfulSceneDefinition: Codable, Sendable, Equatable, Identifiable {
  private enum Limits {
    static let maximumPhases = 12
    static let maximumDuration = 30.0
    static let phaseDuration = 0.2...15.0
    static let headroom = 1.0...4.0
    static let maximumMessageLength = 80
  }
  public enum Trigger: String, Codable, Sendable { case ambient, idle, landing, windowSettled }
  public enum Layout: String, Codable, Sendable { case perches, together, exterior }
  public enum Facing: String, Codable, Sendable { case left, right }
  public enum Travel: String, Codable, Sendable {
    case direct, cornerPullUp, cornerLowering

    var clamberDirection: PlayfulClamberMotion.Direction? {
      switch self {
      case .direct: nil
      case .cornerPullUp: .pullUp
      case .cornerLowering: .lowerDown
      }
    }
  }
  public enum Role: String, Codable, Sendable, CaseIterable { case lead, partner }
  public enum Destination: String, Codable, Sendable { case home, stage, corner, outside, below }
  public enum Prop: String, Codable, Sendable {
    case none, sign, rope, campfire, plane, letter, score, parachute
  }

  public struct Cue: Codable, Sendable, Equatable {
    public struct Staging: Sendable {
      public let pose: AttachmentPose?
      public let facing: Facing?
      public let movementStart: Double?
      public let travel: Travel?

      public init(
        pose: AttachmentPose? = nil, facing: Facing? = nil,
        movementStart: Double? = nil, travel: Travel? = nil
      ) {
        self.pose = pose
        self.facing = facing
        self.movementStart = movementStart
        self.travel = travel
      }
    }
    public let role: Role
    public let animation: AnimationID
    public let destination: Destination
    public let pose: AttachmentPose?
    public let facing: Facing?
    public let movementStart: Double?
    public let travel: Travel?

    public init(
      role: Role, animation: AnimationID, destination: Destination, staging: Staging = .init()
    ) {
      self.role = role
      self.animation = animation
      self.destination = destination
      pose = staging.pose
      facing = staging.facing
      movementStart = staging.movementStart
      travel = staging.travel
    }
  }

  public struct Phase: Codable, Sendable, Equatable {
    public let duration: Double
    public let cues: [Cue]
    public let prop: Prop
    public let motion: PlayfulSceneMotion?
    public let propOwner: Role?
    public var owningRole: Role { propOwner ?? .lead }

    public init(
      duration: Double, cues: [Cue], prop: Prop, propOwner: Role? = nil,
      motion: PlayfulSceneMotion? = nil
    ) {
      self.duration = duration
      self.cues = cues
      self.prop = prop
      self.propOwner = propOwner
      self.motion = motion
    }
  }

  public let id: String
  public let title: String
  public let trigger: Trigger
  public let layout: Layout
  public let participants: Int
  public let cooldown: Double
  public let weight: Double
  public let clearanceAbove: Double
  public let messages: [String]
  public let phases: [Phase]
  public var duration: Double { phases.reduce(0) { $0 + $1.duration } }

  public func validate() throws {
    guard !id.isEmpty, !title.isEmpty, (1...Role.allCases.count).contains(participants),
      cooldown.isFinite, cooldown >= 0, weight.isFinite, weight > 0,
      clearanceAbove.isFinite, Limits.headroom.contains(clearanceAbove),
      !phases.isEmpty, phases.count <= Limits.maximumPhases, duration <= Limits.maximumDuration,
      messages.allSatisfy({ !$0.isEmpty && $0.count <= Limits.maximumMessageLength })
    else { throw CharacterDefinition.ValidationError("Invalid playful scene: \(id)") }
    let roles = Set(Role.allCases.prefix(participants))
    for phase in phases {
      guard phase.duration.isFinite, Limits.phaseDuration.contains(phase.duration),
        Set(phase.cues.map(\.role)) == roles, phase.cues.count == participants,
        phase.cues.allSatisfy({ !$0.animation.rawValue.isEmpty }),
        roles.contains(phase.owningRole),
        phase.motion?.isValid != false,
        phase.cues.allSatisfy({ (0..<1).contains($0.movementStart ?? 0) }),
        phase.cues.allSatisfy({
          $0.pose?.isHanging != true
            || (layout == .exterior && $0.pose == .hangingRight
              && [.outside, .below].contains($0.destination))
        }),
        layout == .exterior || phase.cues.allSatisfy({ [.home, .stage].contains($0.destination) })
      else { throw CharacterDefinition.ValidationError("Invalid phase in playful scene: \(id)") }
    }
    guard phases.last?.cues.allSatisfy({ $0.destination == .home }) == true else {
      throw CharacterDefinition.ValidationError("Playful scene must return home: \(id)")
    }
    for role in roles {
      var previous: Cue?
      for phase in phases {
        guard let cue = phase.cues.first(where: { $0.role == role }) else { continue }
        try validateTravel(cue, previous: previous, motion: phase.motion)
        if cue.destination == .below || previous?.destination == .below {
          guard [.below, .outside].contains(previous?.destination ?? .home),
            [.below, .outside].contains(cue.destination)
          else {
            throw CharacterDefinition.ValidationError("Exterior route must clear the corner: \(id)")
          }
        }
        previous = cue
      }
    }
  }

  private func validateTravel(_ cue: Cue, previous: Cue?, motion: PlayfulSceneMotion?) throws {
    guard let direction = cue.travel?.clamberDirection else { return }
    let grip = direction == .pullUp ? previous : cue
    let landing = direction == .pullUp ? cue : previous
    guard layout == .exterior, grip?.destination == .outside, grip?.pose == .hangingRight,
      landing?.destination == .corner, (landing?.pose ?? .standing) == .standing,
      cue.facing == .left, (cue.movementStart ?? 0) == 0, motion == nil
    else {
      throw CharacterDefinition.ValidationError(
        "Corner travel must connect a ledge and side grip: \(id)")
    }
  }
}
