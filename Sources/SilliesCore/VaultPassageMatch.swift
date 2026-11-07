import Foundation

public struct VaultPassageMatch: Identifiable, Equatable, Sendable {
  public static let maximumPerItem = 20
  public let id: Int64
  public let location: VaultBlockLocation
  public let excerpt: String
  public let startSeconds: Double?
  public init(id: Int64, location: VaultBlockLocation, excerpt: String, startSeconds: Double?) {
    self.id = id
    self.location = location
    self.excerpt = excerpt
    self.startSeconds = startSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
  }
}
