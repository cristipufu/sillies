import Foundation

/// Catalog metadata is independent of inference libraries and installation state.
public struct SpeechModelDescriptor: Codable, Identifiable, Equatable, Sendable {
  public enum Purpose: String, Codable, Sendable { case transcription, speakerDiarization }
  public struct Capabilities: Codable, Equatable, Sendable {
    public enum LanguageControl: String, Codable, Sendable { case automatic, selectable }
    public let languageControl: LanguageControl
    public let languages: [String]
    public let supportsAutomaticDetection: Bool
    public let requiresAppleSilicon: Bool
    public var maximumSpeakers: Int? = nil

    public init(
      languageControl: LanguageControl, languages: [String], supportsAutomaticDetection: Bool,
      requiresAppleSilicon: Bool = true
    ) {
      self.languageControl = languageControl
      self.languages = languages
      self.supportsAutomaticDetection = supportsAutomaticDetection
      self.requiresAppleSilicon = requiresAppleSilicon
    }
  }

  public let id: String
  public let providerID: String
  public let name: String
  public let detail: String
  public private(set) var revision: String
  public let capabilities: Capabilities
  public let license: String
  public let sourceURL: String
  public var purpose: Purpose? = nil

  public var isDiarizationModel: Bool { purpose == .speakerDiarization }

  public func revised(to revision: String) -> Self {
    var result = self
    result.revision = revision
    return result
  }

  public var isSystemManaged: Bool { id == Self.apple.id }
  public var provenance: SpeechProvenance {
    SpeechProvenance(providerID: providerID, modelID: id, revision: revision, modelName: name)
  }

  public static let apple = SpeechModelDescriptor(
    id: "apple-speech", providerID: "apple", name: "Apple Speech",
    detail: "Uses speech languages installed by macOS.",
    revision: "system",
    capabilities: .init(
      languageControl: .selectable, languages: [], supportsAutomaticDetection: false,
      requiresAppleSilicon: false),
    license: "Provided by macOS", sourceURL: "https://developer.apple.com/documentation/speech")
}
