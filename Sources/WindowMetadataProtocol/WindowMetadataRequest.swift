import Foundation

public enum WindowMetadataRequest: Codable, Sendable {
  public static let maximumTargetWindows = 256
  case windowList(options: UInt32, reference: UInt32)
  case windows([UInt32])

  public init(options: UInt32, reference: UInt32) {
    self = .windowList(options: options, reference: reference)
  }
}
