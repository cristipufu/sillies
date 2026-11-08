import Foundation

/// Publisher-supplied credit for an optional model. It is shown wherever that model speaks.
public struct ModelAttribution: Codable, Equatable, Sendable {
  private static let maximumCreditCharacters = 160
  public let text: String
  public let url: URL

  public init(text: String, url: URL) {
    self.text = text
    self.url = url
  }

  public var isValid: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && text.count <= Self.maximumCreditCharacters
      && url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
  }
}
