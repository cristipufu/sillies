import Foundation

/// Bounded listing data. A header is never a partially loaded SessionRecord.
public struct SessionRecordHeader: Codable, Identifiable, Equatable, Sendable {
  public static let previewLimit = 240
  private static let labelLimit = 1_024
  public let id: UUID
  public let kind: CompanionSkillKind
  public let characterID: String
  public let characterName: String
  public let appName: String
  public let windowTitle: String?
  public let createdAt: Date
  public let durationSeconds: Double
  public let preview: String
  public let stashItemCount: Int
  public let isProtected: Bool
  public let summaryPending: Bool
  public let screenshotRevision: UUID
  public let screenshotTextState: ScreenshotTextState
  public let imageFilename: String?
  public let audioFilename: String?
  public let failure: SessionFailure?
  public var requiresPermissionAccess: Bool { failure?.recovery != nil }

  public init(_ record: SessionRecord) {
    id = record.id
    kind = record.kind
    characterID = record.characterID
    characterName = String(record.characterName.prefix(Self.labelLimit))
    appName = String(record.appName.prefix(Self.labelLimit))
    windowTitle = record.windowTitle.map { String($0.prefix(Self.labelLimit)) }
    createdAt = record.createdAt
    durationSeconds = record.durationSeconds
    let source =
      record.kind == .stash
      ? record.stashedItems.first ?? record.summary
      : !record.summary.isEmpty
        ? record.summary : !record.transcript.isEmpty ? record.transcript : record.extractedText
    preview = String(source.prefix(Self.previewLimit))
    stashItemCount = record.stashedItems.count
    isProtected = record.isProtected
    summaryPending = record.summaryPending
    screenshotTextState = record.screenshotTextState
    screenshotRevision = record.processingRevision.screenshot
    imageFilename = record.imageFilename
    audioFilename = record.audioFilename
    failure = record.failure.map {
      SessionFailure(
        category: $0.category, message: String($0.message.prefix(Self.labelLimit)),
        recovery: $0.recovery)
    }
  }
}
