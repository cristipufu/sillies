import Foundation

/// A participant label is display data, never transcript syntax or a global voice identity.
public struct CallSpeakerName: RawRepresentable, Hashable, Codable, Sendable {
  public static let maximumCharacters = 80
  public static let maximumUTF8Bytes = 1_024
  public let rawValue: String
  public init?(rawValue: String) {
    guard rawValue.utf8.count <= Self.maximumUTF8Bytes else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    guard !value.isEmpty, value.utf8.count <= Self.maximumUTF8Bytes,
      value.count <= Self.maximumCharacters,
      !value.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
      })
    else { return nil }
    self.rawValue = value
  }
  public var transcriptLabel: String { rawValue.replacingOccurrences(of: ":", with: "：") }
  public var comparisonKey: String {
    rawValue.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let name = Self(rawValue: value) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid call participant name"))
    }
    self = name
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
