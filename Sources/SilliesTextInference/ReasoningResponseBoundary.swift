/// Validates the visible side of a configured reasoning protocol across arbitrary stream chunks.
/// The native emitter consumes paired delimiters; an orphaned closing delimiter is a protocol error.
struct ReasoningResponseBoundary {
  enum Failure: Error { case unexpectedClose }
  private let closingDelimiter: String
  private var pending = ""

  init(closingDelimiter: String) {
    self.closingDelimiter = closingDelimiter
  }

  mutating func append(_ text: String) throws -> String {
    guard !closingDelimiter.isEmpty else { return text }
    pending += text
    guard !pending.contains(closingDelimiter) else { throw Failure.unexpectedClose }
    let heldCount =
      (1..<closingDelimiter.count).reversed().first {
        pending.hasSuffix(closingDelimiter.prefix($0))
      } ?? 0
    let visible = String(pending.dropLast(heldCount))
    pending = String(pending.suffix(heldCount))
    return visible
  }

  mutating func finish() -> String {
    defer { pending = "" }
    return pending
  }
}
