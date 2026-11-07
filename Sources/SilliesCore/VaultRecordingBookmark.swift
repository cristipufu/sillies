import Foundation

public struct VaultRecordingBookmark: Codable, Identifiable, Equatable, Sendable {
  public static let maximumPerRecording = 200
  public static let maximumLabelScalars = 256
  public let id: UUID
  public let recordID: UUID
  public let seconds: Double
  public let label: String
  public init(id: UUID = UUID(), recordID: UUID, seconds: Double, label: String) {
    self.id = id
    self.recordID = recordID
    self.seconds = seconds
    self.label = label
  }
  public var isValid: Bool {
    seconds.isFinite && seconds >= 0 && label.unicodeScalars.count <= Self.maximumLabelScalars
  }
}
