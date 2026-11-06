/// A refusal is explicit evidence of no operation, never an empty successful search or save.
struct ToolNotExecutedResult: Encodable {
  enum Reason: String, Encodable {
    case turnToolLimitReached, recoveryReplayOnly, awaitingUserAnswer
  }
  let status = "notExecuted"
  let reason: Reason
  var remainingCalls: Int? { reason == .turnToolLimitReached ? 0 : nil }
  var coverage: String {
    switch reason {
    case .turnToolLimitReached:
      "No operation was performed. The tool allowance for this turn is exhausted. Answer from the results already returned and state any missing evidence; do not request more tools."
    case .recoveryReplayOnly:
      "No operation was performed. This response is recovering from an invalid model response. Only identical previously completed tool calls can replay their results; new operations are unavailable. Use returned evidence and state what could not be completed."
    case .awaitingUserAnswer:
      "No operation was performed. A clarification is already awaiting the user's answer. Ask the pending question and stop; do not choose for the user."
    }
  }
  private enum CodingKeys: String, CodingKey { case status, reason, remainingCalls, coverage }
  func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(status, forKey: .status)
    try values.encode(reason, forKey: .reason)
    try values.encodeIfPresent(remainingCalls, forKey: .remainingCalls)
    try values.encode(coverage, forKey: .coverage)
  }
}
