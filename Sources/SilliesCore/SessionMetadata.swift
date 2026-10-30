import Foundation

/// Identity, time, and language metadata supplied when creating a saved session.
public struct SessionMetadata: Sendable {
  public let id: UUID
  public let createdAt: Date
  public let durationSeconds: Double
  public let languageIdentifier: String?

  public init(
    id: UUID = UUID(), createdAt: Date = Date(), durationSeconds: Double = 0,
    languageIdentifier: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.durationSeconds = durationSeconds
    self.languageIdentifier = languageIdentifier
  }
}
