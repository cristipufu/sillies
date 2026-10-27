import Foundation

public struct WindowMetadataRequest: Codable, Sendable {
  public let options: UInt32
  public let reference: UInt32

  public init(options: UInt32, reference: UInt32) {
    self.options = options
    self.reference = reference
  }
}
