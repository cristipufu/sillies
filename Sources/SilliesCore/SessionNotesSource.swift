/// Distinguishes generated summaries from source excerpts without inspecting their text.
public enum SessionNotesSource: String, Codable, Sendable {
  case unspecified, generated, extracted

  public var title: String {
    switch self {
    case .unspecified: "Notes & Highlights"
    case .generated: "Summary & Highlights"
    case .extracted: "Extracted Highlights"
    }
  }
}
