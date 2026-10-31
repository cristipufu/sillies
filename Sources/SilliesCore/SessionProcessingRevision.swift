import Foundation

/// Independent generations let notes and OCR reject results from superseded work.
public struct SessionProcessingRevision: Codable, Equatable, Sendable {
  public private(set) var notes: UUID
  public private(set) var screenshot: UUID
  public init(seed: UUID) {
    notes = seed
    screenshot = seed
  }
  public mutating func renewNotes() { notes = UUID() }
  public mutating func renewScreenshot() { screenshot = UUID() }
}
