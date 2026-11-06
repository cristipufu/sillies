import Foundation

public struct SearchEmbeddingInput: Codable, Sendable {
  public enum Purpose: String, Codable, Sendable { case query, passage }
  public let text: String
  public let purpose: Purpose
  public init(text: String, purpose: Purpose) {
    self.text = text
    self.purpose = purpose
  }
}
