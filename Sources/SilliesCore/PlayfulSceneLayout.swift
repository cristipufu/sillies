import CoreGraphics
import Foundation

/// Validates the complete stage before reserving a cast. No route crosses the document.
public enum PlayfulSceneLayout {
  private static let stageGapRatio = 2.2
  private static let maximumStageWidth: Double = 460
  private static let descentRatio = 2.3
  private static let exteriorInsetRatio = 0.8
  private static let cornerSpacingRatio = 0.8
  private static let cornerInsetRatio = 0.7

  public struct Request: Sendable {
    public let definition: PlayfulSceneDefinition
    public let participants: [PlayfulSceneParticipant]
    public let bystanders: [PlayfulSceneParticipant]
    public let window: CGRect?
    public let visibleFrame: CGRect
    public let message: String
    public let occupiedFrames: [CGRect]

    public init(
      definition: PlayfulSceneDefinition, participants: [PlayfulSceneParticipant],
      bystanders: [PlayfulSceneParticipant], window: CGRect?, visibleFrame: CGRect, message: String,
      occupiedFrames: [CGRect] = []
    ) {
      self.definition = definition
      self.participants = participants
      self.bystanders = bystanders
      self.window = window
      self.visibleFrame = visibleFrame
      self.message = message
      self.occupiedFrames = occupiedFrames
    }
  }

  public static func plan(_ request: Request) -> PlayfulScenePlan? {
    let cast = request.participants
    guard let first = cast.first, cast.count == request.definition.participants,
      [.top, .desktop].contains(first.surface.edge),
      cast.allSatisfy({ $0.surface == first.surface && $0.windowID == first.windowID })
    else { return nil }
    let size = first.surface.presentationSize
    guard
      request.visibleFrame.maxY - first.position.y
        >= PlayfulPropLayout.requiredHeadroom(for: request.definition, size: size)
    else { return nil }
    let actors = makeActors(request, first: first)
    guard hasClearStage(actors, request: request, first: first) else { return nil }
    if request.definition.layout == .exterior,
      !hasClearExterior(actors, request: request, first: first)
    {
      return nil
    }

    return PlayfulScenePlan(
      definition: request.definition, actors: actors,
      message: request.message, visibleFrame: request.visibleFrame, window: request.window)
  }

  private static func makeActors(_ request: Request, first: PlayfulSceneParticipant)
    -> [PlayfulScenePlan.Actor]
  {
    let cast = request.participants
    let size = first.surface.presentationSize
    let center = cast.reduce(0) { $0 + $1.position.x } / Double(cast.count)
    return cast.enumerated().map { index, participant in
      let slot = Double(index) - Double(cast.count - 1) / 2
      let stage =
        request.definition.layout == .perches
        ? participant.position
        : CGPoint(x: center + slot * size * stageGapRatio, y: first.position.y)
      let corner = CGPoint(
        x: (request.window.map { Double($0.maxX) } ?? center) - size
          * (cornerInsetRatio + Double(cast.count - 1 - index) * cornerSpacingRatio),
        y: stage.y)
      let outside = CGPoint(
        x: (request.window.map { Double($0.maxX) } ?? center) + size * exteriorInsetRatio,
        y: stage.y)
      return PlayfulScenePlan.Actor(
        participant: participant,
        role: PlayfulSceneDefinition.Role.allCases[index], stage: stage, corner: corner,
        outside: outside, below: CGPoint(x: outside.x, y: outside.y - size * descentRatio),
        exteriorEdgeX: request.window.map { Double($0.maxX) } ?? center)
    }
  }

  private static func motionClearance(_ request: Request, size: Double) -> Double {
    (request.definition.phases.compactMap { $0.motion?.distance }.max() ?? 0) * size
  }

  private static func hasClearStage(
    _ actors: [PlayfulScenePlan.Actor], request: Request, first: PlayfulSceneParticipant
  ) -> Bool {
    let size = first.surface.presentationSize
    guard
      actors.allSatisfy({ first.surface.minX <= $0.stage.x && $0.stage.x <= first.surface.maxX })
    else { return false }
    let motion = motionClearance(request, size: size)
    let positions: [CGFloat] = actors.flatMap {
      [$0.stage.x - motion, $0.stage.x + motion, $0.participant.position.x]
    }
    guard let left = positions.min(), let right = positions.max(),
      request.definition.layout == .perches || right - left <= maximumStageWidth,
      first.surface.minX <= left, right <= first.surface.maxX
    else { return false }
    let clearance = PerchSpacing.separation(between: size, and: size)
    guard
      !request.bystanders.contains(where: {
        $0.surface == first.surface && $0.windowID == first.windowID
          && $0.position.x > left - clearance && $0.position.x < right + clearance
      })
    else { return false }
    let corridor = occupiedCorridor(actors, request: request, first: first)
    return !request.occupiedFrames.contains(where: { $0.intersects(corridor) })
  }

  private static func occupiedCorridor(
    _ actors: [PlayfulScenePlan.Actor], request: Request, first: PlayfulSceneParticipant
  ) -> CGRect {
    let size = first.surface.presentationSize
    let motion = motionClearance(request, size: size)
    let positions: [CGFloat] = actors.flatMap {
      [$0.stage.x - motion, $0.stage.x + motion, $0.participant.position.x]
    }
    let left = positions.min() ?? first.position.x
    let right = positions.max() ?? first.position.x
    let exterior = request.definition.layout == .exterior
    let routeRight = exterior ? max(right, actors.map(\.outside.x).max() ?? right) : right
    let routeBottom = exterior ? actors.map(\.below.y).min() ?? first.position.y : first.position.y
    let clearance = PerchSpacing.separation(between: size, and: size)
    return CGRect(
      x: left - clearance / 2, y: routeBottom,
      width: routeRight - left + clearance,
      height: first.position.y - routeBottom + size * request.definition.clearanceAbove)
  }

  private static func hasClearExterior(
    _ actors: [PlayfulScenePlan.Actor], request: Request, first: PlayfulSceneParticipant
  ) -> Bool {
    let size = first.surface.presentationSize
    let left = actors.map { min($0.stage.x, $0.participant.position.x) }.min() ?? first.position.x
    let clearance = PerchSpacing.separation(between: size, and: size)
    guard let window = request.window, first.surface.edge == .top,
      actors.allSatisfy({ first.surface.minX <= $0.corner.x && $0.corner.x <= first.surface.maxX }),
      request.visibleFrame.maxX - window.maxX >= size
        * CompanionWindowLayout.exteriorSceneClearanceRatio,
      first.position.y - size * descentRatio > max(window.minY, request.visibleFrame.minY) + size
    else { return false }
    return !request.bystanders.contains(where: {
      $0.windowID == first.windowID && $0.position.x > left - clearance
    })
  }

}
