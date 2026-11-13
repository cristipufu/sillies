import Foundation

/// Normalization shared by independent call-app adapters.
enum CallSpeakerText {
  static let maximumMetadataBytes = 1_024
  static func normalize(_ value: String) -> String {
    value.precomposedStringWithCompatibilityMapping.lowercased().trimmingCharacters(
      in: .whitespacesAndNewlines)
  }
  static func removingSuffixes(_ suffixes: [String], from raw: String) -> String {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let suffix = suffixes.first(where: { normalize(name).hasSuffix(normalize($0)) }) {
      name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }
    return name
  }
}
