/// Keeps the tokenized dictionary for one loaded tokenizer. A changed dictionary replaces it.
struct WhisperVocabularyPrompt {
  private static let maximumTokens = 160
  private var words: [String] = []
  private var encoded: [Int]?

  mutating func tokens(for vocabulary: [String], encode: (String) -> [Int]) -> [Int]? {
    guard !vocabulary.isEmpty else {
      words = []
      encoded = nil
      return nil
    }
    if words == vocabulary, let encoded { return encoded }
    let tokens = Array(encode(vocabulary.joined(separator: ", ")).prefix(Self.maximumTokens))
    words = vocabulary
    encoded = tokens
    return tokens
  }
}
