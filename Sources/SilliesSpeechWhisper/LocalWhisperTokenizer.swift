import Foundation
import NaturalLanguage
import SilliesSpeech
@preconcurrency import WhisperKit

/// Supplies the SDK's tokenizer contract from verified local files, without its Hub fallback.
struct LocalWhisperTokenizer: WhisperTokenizer {
  private let tokenizer: TokenizerWrapper
  let specialTokens: SpecialTokens
  let allLanguageTokens: Set<Int>

  init(tokenizer: TokenizerWrapper) throws {
    self.tokenizer = tokenizer
    func token(_ text: String) throws -> Int {
      guard let id = tokenizer.convertTokenToId(text) else {
        throw SpeechError.unavailable(
          "The downloaded Whisper tokenizer is missing \(text). Download the model again.")
      }
      return id
    }
    let whitespace = tokenizer.encode(text: " ", addSpecialTokens: false)
    guard whitespace.count == 1, let whitespaceToken = whitespace.first else {
      throw SpeechError.unavailable("Whisper's tokenizer cannot encode a word separator.")
    }
    specialTokens = try SpecialTokens(
      endToken: token("<|endoftext|>"), englishToken: token("<|en|>"),
      noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"),
      specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"),
      startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
      transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"),
      whitespaceToken: whitespaceToken)
    allLanguageTokens = Set(
      Constants.languages.values.compactMap { tokenizer.convertTokenToId("<|\($0)|>") })
  }

  func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
  func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
  func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }

  func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
    let text = decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin })
    let language = NLLanguageRecognizer.dominantLanguage(for: text).map {
      Locale(identifier: $0.rawValue).language.languageCode?.identifier
    }
    let units = unicodeUnits(tokenIds)
    if ["zh", "ja", "th", "lo", "my", "yue"].contains(language ?? nil) {
      return (units.map(\.text), units.map(\.tokens))
    }
    var words: [Unit] = []
    for unit in units {
      let trimmed = unit.text.trimmingCharacters(in: .whitespaces)
      let punctuation =
        trimmed.unicodeScalars.count == 1
        && trimmed.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
      let special = unit.tokens.first.map { $0 >= specialTokens.specialTokenBegin } == true
      if words.isEmpty || special || punctuation || unit.text.hasPrefix(" ") {
        words.append(unit)
      } else {
        words[words.count - 1].text += unit.text
        words[words.count - 1].tokens += unit.tokens
      }
    }
    return (words.map(\.text), words.map(\.tokens))
  }

  private struct Unit {
    var text: String
    var tokens: [Int]
  }

  private func unicodeUnits(_ tokens: [Int]) -> [Unit] {
    var units: [Unit] = []
    var pending: [Int] = []
    for token in tokens {
      pending.append(token)
      let decoded = decode(tokens: pending)
      // Byte-pair tokens can end halfway through a Romanian diacritic or another scalar.
      guard !decoded.contains("\u{fffd}") else { continue }
      units.append(Unit(text: decoded, tokens: pending))
      pending.removeAll(keepingCapacity: true)
    }
    if !pending.isEmpty { units.append(Unit(text: decode(tokens: pending), tokens: pending)) }
    return units
  }
}
