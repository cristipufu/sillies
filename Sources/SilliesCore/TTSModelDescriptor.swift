import Foundation

/// Download and presentation metadata; runtime implementations live outside the domain.
public struct TTSModelDescriptor: Codable, Equatable, Identifiable, Sendable {
  public static let supportedOutputSampleRates = 8_000...96_000
  public let id: String
  public let providerID: String
  public let runtimeVariant: String
  public let name: String
  public var family: String? = nil
  public let detail: String
  public let revision: String
  public let license: String
  public let sourceURL: URL
  public let minimumMemoryGB: Int
  public let languages: [String]
  public let voices: [TTSVoice]
  public let streamsAudio: Bool
  public let outputSampleRate: Int?

  public func supports(language: String) -> Bool {
    let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
    return languages.contains { normalized == $0 || normalized.hasPrefix($0 + "-") }
  }
}

public struct TTSVoice: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let languages: [String]

  public func supports(language: String) -> Bool {
    let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
    return languages.contains { normalized == $0 || normalized.hasPrefix($0 + "-") }
  }
}
