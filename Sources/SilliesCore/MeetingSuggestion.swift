import Foundation

public struct MeetingSuggestion: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let question: String
  public let evidence: String
  public let elapsed: TimeInterval

  public init(question: String, evidence: String, elapsed: TimeInterval) {
    id = UUID()
    self.question = question
    self.evidence = evidence
    self.elapsed = elapsed
  }
}

/// Limits interruptions and rejects suggestions that cannot be traced to the transcript.
public struct MeetingSuggestionGate: Sendable {
  public static let minimumInterval: TimeInterval = 45
  public static let maximumSuggestions = 12
  private static let minimumEvidenceCharacters = 12
  public private(set) var suggestions: [MeetingSuggestion] = []

  public init() {}

  public mutating func accept(_ suggestion: MeetingSuggestion, source: String) -> Bool {
    let question = suggestion.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let evidence = suggestion.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, evidence.count >= Self.minimumEvidenceCharacters,
      source.localizedCaseInsensitiveContains(evidence),
      suggestions.count < Self.maximumSuggestions,
      !suggestions.contains(where: {
        $0.question.lowercased() == question.lowercased()
          || $0.evidence.lowercased() == evidence.lowercased()
      }),
      suggestions.last.map({ suggestion.elapsed - $0.elapsed >= Self.minimumInterval }) ?? true
    else { return false }
    suggestions.append(suggestion)
    return true
  }
}
