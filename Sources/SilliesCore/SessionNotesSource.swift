import Foundation

/// Distinguishes generated summaries from source excerpts without inspecting their text.
public enum SessionNotesSource: String, Codable, Sendable {
  case unspecified, generated, extracted

  public var title: String {
    switch self {
    case .unspecified: String(localized: "Notes & Highlights")
    case .generated: String(localized: "Summary & Highlights")
    case .extracted: String(localized: "Extracted Highlights")
    }
  }
}
