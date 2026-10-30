import Foundation

/// Identity, time, and language metadata supplied when creating a saved session.
public struct SessionMetadata: Sendable {
  public let id: UUID
  public let createdAt: Date
  public let durationSeconds: Double
  public let transcription: SessionTranscriptionMetadata

  public init(
    id: UUID = UUID(), createdAt: Date = Date(), durationSeconds: Double = 0,
    transcription: SessionTranscriptionMetadata = .init()
  ) {
    self.id = id
    self.createdAt = createdAt
    self.durationSeconds = durationSeconds
    self.transcription = transcription
  }
}
