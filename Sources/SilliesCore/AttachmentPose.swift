import CoreGraphics

public enum AttachmentPose: Sendable, Hashable {
  public static let designCanvasSize: Double = 128
  public static let standingAnchor = CGPoint(x: 64, y: 20)
  public static let hangingLeftAnchor = CGPoint(x: 112, y: 101)
  public static let hangingRightAnchor = CGPoint(x: 16, y: 101)

  case standing, hangingLeft, hangingRight

  public var anchor: CGPoint {
    switch self {
    case .standing: Self.standingAnchor
    case .hangingLeft: Self.hangingLeftAnchor
    case .hangingRight: Self.hangingRightAnchor
    }
  }

  public var isHanging: Bool { self != .standing }
}

extension PerchSurface {
  public var attachmentPose: AttachmentPose {
    switch edge {
    case .left: .hangingLeft
    case .right: .hangingRight
    default: .standing
    }
  }
}
