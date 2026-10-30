import CoreGraphics
import Foundation

public struct PlayfulSceneParticipant: Sendable {
  public let id: String
  public let profile: PlayfulCharacterProfile
  public let surface: PerchSurface
  public let position: CGPoint
  public let windowID: UInt32?

  public init(
    id: String, profile: PlayfulCharacterProfile, surface: PerchSurface,
    position: CGPoint, windowID: UInt32?
  ) {
    self.id = id
    self.profile = profile
    self.surface = surface
    self.position = position
    self.windowID = windowID
  }
}

public struct PlayfulScenePlan: Sendable {
  public struct Actor: Sendable {
    private static let ropeClearance: Double = 6
    private static let ropeBendDrop: Double = 6.5
    public let participant: PlayfulSceneParticipant
    public let role: PlayfulSceneDefinition.Role
    public let stage: CGPoint
    public let corner: CGPoint
    public let outside: CGPoint
    public let below: CGPoint
    public let exteriorEdgeX: Double

    public func point(
      for destination: PlayfulSceneDefinition.Destination, pose: AttachmentPose = .standing
    ) -> CGPoint {
      let point: CGPoint =
        switch destination {
        case .home: participant.position
        case .stage: stage
        case .corner: corner
        case .outside: outside
        case .below: below
        }
      guard pose.isHanging else { return point }
      let offset = pose.contactOffset(from: .standing, size: participant.surface.presentationSize)
      return CGPoint(
        x: exteriorEdgeX + Self.ropeClearance - offset.x,
        y: destination == .outside ? point.y - offset.y - Self.ropeBendDrop : point.y)
    }
  }
  public let definition: PlayfulSceneDefinition
  public let actors: [Actor]
  public let message: String
  public let visibleFrame: CGRect
  public let window: CGRect?
}
