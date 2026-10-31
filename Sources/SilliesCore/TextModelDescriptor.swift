import Foundation

public struct TextModelDescriptor: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let providerID: String
  public let name: String
  public let detail: String
  public let revision: String
  public let license: String
  public let sourceURL: URL
  public let minimumMemoryGB: Int
  public let contextTokens: Int
  public let languagesDescription: String
}
