import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

/// WhisperKit's default loader can download a tokenizer even with download=false.
/// This override fails locally instead; model installation is the sole network owner.
final class OfflineWhisperKit: WhisperKit {
  override func loadTokenizerIfNeeded() async throws {
    guard tokenizer == nil else { return }
    guard let modelFolder, let vocabularySize = textDecoder.logitsSize else {
      throw SpeechError.unavailable("Whisper's local model files are incomplete.")
    }
    let local = try await AutoTokenizerWrapper.from(modelFolder: modelFolder)
    tokenizer = try LocalWhisperTokenizer(tokenizer: local)
    textDecoder.isModelMultilingual = vocabularySize != Self.englishVocabularySize
  }

  private static let englishVocabularySize = 51_864
}
