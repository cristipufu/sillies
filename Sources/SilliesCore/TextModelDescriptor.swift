import Foundation

public struct TextModelDescriptor: Codable, Equatable, Identifiable, Sendable {
  public struct Release: Codable, Equatable, Sendable {
    /// Original model release, not the date its quantized checkpoint was uploaded.
    public let date: String
    public let sourceURL: URL
  }
  public let id: String
  public let providerID: String
  public let name: String
  public let detail: String
  public let revision: String
  public let license: String
  public let sourceURL: URL
  public let minimumMemoryGB: Int
  public let profile: TextModelProfile
  public var contextTokens: Int { profile.context.workingTokens }
  public let languagesDescription: String
  public let release: Release?
  public let reasoning: TextModelReasoning?
}
