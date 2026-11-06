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
  public var family: String? = nil
  public let detail: String
  public let revision: String
  public let license: String
  public let sourceURL: URL
  public let minimumMemoryGB: Int
  public private(set) var profile: TextModelProfile
  public var contextTokens: Int { profile.context.workingTokens }
  public let languagesDescription: String
  public let release: Release?
  public let reasoning: TextModelReasoning?
  public func processingPrefill(inChunksOf tokens: Int) -> Self? {
    guard let profile = profile.processingPrefill(inChunksOf: tokens) else { return nil }
    var copy = self
    copy.profile = profile
    return copy
  }
}
