import Foundation

/// Recovery is explicit domain data; user-facing wording never selects an action.
public struct SessionFailure: Error, LocalizedError, Codable, Equatable, Sendable {
  public enum Category: String, Codable, Sendable {
    case permissionDenied, captureUnavailable, captureInterrupted, audioProcessing
    case transcription, recordingSave, finalization, unknown
  }
  public enum RecoveryAction: String, Codable, Sendable {
    case openMicrophoneSettings, openScreenRecordingSettings
  }

  public let message: String
  private let categoryIdentifier: String
  private let recoveryIdentifier: String?
  public var category: Category { Category(rawValue: categoryIdentifier) ?? .unknown }
  public var recovery: RecoveryAction? {
    guard category == .permissionDenied else { return nil }
    return recoveryIdentifier.flatMap(RecoveryAction.init(rawValue:))
  }
  public var errorDescription: String? { message }

  public init(category: Category, message: String, recovery: RecoveryAction? = nil) {
    categoryIdentifier = category.rawValue
    self.message = message
    recoveryIdentifier = recovery?.rawValue
  }

  public init(_ error: Error, category: Category) {
    self = error as? SessionFailure ?? Self(category: category, message: error.localizedDescription)
  }

  private enum CodingKeys: String, CodingKey { case category, message, recovery }

  /// Unknown string identifiers survive load/save; malformed required fields still fail decoding.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    categoryIdentifier = try container.decode(String.self, forKey: .category)
    message = try container.decode(String.self, forKey: .message)
    recoveryIdentifier = try container.decodeIfPresent(String.self, forKey: .recovery)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(categoryIdentifier, forKey: .category)
    try container.encode(message, forKey: .message)
    try container.encodeIfPresent(recoveryIdentifier, forKey: .recovery)
  }

  public static func permissionDenied(_ recovery: RecoveryAction) -> Self {
    let message: String
    switch recovery {
    case .openMicrophoneSettings:
      message =
        "Microphone access is required. Enable Sillies in microphone settings, then start a new session."
    case .openScreenRecordingSettings:
      message =
        "Screen and system audio access is required. Enable Sillies in recording settings, then start a new session."
    }
    return Self(category: .permissionDenied, message: message, recovery: recovery)
  }
}
