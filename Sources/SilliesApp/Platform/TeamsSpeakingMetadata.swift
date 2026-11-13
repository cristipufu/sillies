import Foundation

/// Parses a complete status label; ordinary text mentioning speech cannot match a prefix alone.
enum TeamsSpeakingMetadata {
  static func participant(in label: String) -> CallParticipantLabel? {
    guard label.utf8.count <= CallSpeakerText.maximumMetadataBytes else { return nil }
    let text = label.precomposedStringWithCompatibilityMapping
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let normalized = CallSpeakerText.normalize(text)
    if let colon = text.firstIndex(of: ":") {
      let heading = CallSpeakerText.normalize(String(text[..<colon]))
      guard ["active speaker", "now speaking", "speaking now"].contains(heading) else { return nil }
      return CallParticipantLabel(String(text[text.index(after: colon)...]))
    }
    if let fields = CallMetadataFields(text)?.values, fields.count > 1,
      let status = fields.last, ["speaking", "talking"].contains(CallSpeakerText.normalize(status))
    {
      return CallParticipantLabel(fields.dropLast().joined(separator: ", "))
    }
    for suffix in [" is speaking", " is talking"] {
      if normalized.hasSuffix(suffix) {
        return CallParticipantLabel(String(text.dropLast(suffix.count)))
      }
    }
    return nil
  }
}
