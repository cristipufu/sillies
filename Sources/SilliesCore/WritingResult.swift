import Foundation

public struct WritingResult: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let createdAt: Date
  public let originalText: String
  public var text: String
  public let applicationName: String
  public var delivery: Delivery
  public var notice: String
  public enum Delivery: String, Codable, Sendable { case ready, inserted, needsPaste }

  public init(originalText: String, text: String, applicationName: String, notice: String = "") {
    id = UUID()
    createdAt = Date()
    self.originalText = originalText
    self.text = text
    self.applicationName = applicationName
    self.notice = notice
    delivery = .ready
  }
}
