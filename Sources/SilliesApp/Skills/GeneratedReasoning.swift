import FoundationModels

@Generable
struct GeneratedNotes: Codable, Sendable {
  @Guide(description: "A concise factual summary of the supplied source only.")
  var summary: String
  @Guide(
    description:
      "For Explain: a plain-language explanation of the visible text, with uncertainty stated. Otherwise empty."
  )
  var explanation: String
}

@Generable
struct GeneratedActionEvidence: Codable, Sendable {
  @Guide(
    description:
      "Every source sentence that explicitly commits to a task, copied verbatim. Include all separate assignments and promises. Preserve names and dates. Empty if no commitments."
  )
  var passages: [String]
}

@Generable
struct GeneratedSuggestion: Codable, Sendable {
  @Guide(
    description:
      "One short, useful clarification question about an unresolved point. Empty if nothing warrants interrupting."
  )
  var question: String
  @Guide(
    description:
      "An exact, contiguous quotation from the source supporting the question. Empty if no question."
  )
  var evidence: String
}
