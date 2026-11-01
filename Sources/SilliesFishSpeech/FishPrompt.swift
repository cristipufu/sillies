import Foundation
import Tokenizers

struct FishPrompt {
  let tokenizer: any Tokenizer
  let configuration: FishConfiguration
  private let prefix: [Int]
  private let suffix: [Int]

  init(tokenizer: any Tokenizer, configuration: FishConfiguration) {
    self.tokenizer = tokenizer
    self.configuration = configuration
    // Preserve the original segment boundaries: joining strings can change BPE tokenization.
    prefix = [
      "<|im_start|>system\n", "convert the provided text to speech", "<|im_end|>\n",
      "<|im_start|>user\n",
    ].flatMap { tokenizer.encode(text: $0, addSpecialTokens: false) }
    suffix = ["<|im_end|>\n", "<|im_start|>assistant\n<|voice|>"].flatMap {
      tokenizer.encode(text: $0, addSpecialTokens: false)
    }
  }

  func validateTokenizer() throws {
    guard tokenizer.convertTokenToId("<|im_end|>") == configuration.eosTokenId else {
      throw FishError.invalidTokenizer
    }
    for index in 0..<FishConfiguration.semanticVocabularySize {
      guard
        tokenizer.convertTokenToId("<|semantic:\(index)|>") == configuration.semanticStartTokenId
          + index
      else {
        throw FishError.invalidTokenizer
      }
    }
  }

  func tokens(for text: String) throws -> [Int32] {
    let content = text.replacingOccurrences(of: "<|", with: "‹|")
    let tokens = prefix + tokenizer.encode(text: content, addSpecialTokens: false) + suffix
    guard !tokens.isEmpty, tokens.count <= FishConfiguration.maximumPromptTokens,
      tokens.allSatisfy({ $0 >= 0 && $0 < configuration.textConfig.vocabSize })
    else { throw FishError.invalidTokenizer }
    return tokens.map(Int32.init)
  }
}
