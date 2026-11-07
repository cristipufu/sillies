import Foundation

public struct VaultContentBlock: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let location: VaultBlockLocation
  public let revision: UUID
  public let text: String
  public let startSeconds: Double?
  public let speaker: String?

  public init(
    id: Int64, location: VaultBlockLocation, revision: UUID, text: String,
    startSeconds: Double? = nil, speaker: String? = nil
  ) {
    self.id = id
    self.location = location
    self.revision = revision
    self.text = text
    self.startSeconds = startSeconds
    self.speaker = speaker
  }
}
