/// Validates the visible side of a configured reasoning protocol across arbitrary stream chunks.
/// The native emitter consumes valid framing; remaining control markers are protocol errors.
struct ReasoningResponseBoundary {
  enum Failure: Error { case unexpectedDelimiter }
  private let delimiters: [String]
  private var pending = ""

  init(delimiters: [String]) {
    self.delimiters = delimiters.filter { !$0.isEmpty }
  }

  mutating func append(_ text: String) throws -> String {
    guard !delimiters.isEmpty else { return text }
    pending += text
    guard !delimiters.contains(where: { pending.contains($0) }) else {
      throw Failure.unexpectedDelimiter
    }
    let heldCount = delimiters.reduce(0) { longest, delimiter in
      let length =
        (1..<delimiter.count).reversed().first {
          pending.hasSuffix(delimiter.prefix($0))
        } ?? 0
      return max(longest, length)
    }
    let visible = String(pending.dropLast(heldCount))
    pending = String(pending.suffix(heldCount))
    return visible
  }

  mutating func finish() -> String {
    defer { pending = "" }
    return pending
  }
}
