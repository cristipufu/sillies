import Foundation
import Tokenizers

struct FishPrompt {
  let tokenizer: any Tokenizer
  let configuration: FishConfiguration

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
    let segments = [
      "<|im_start|>system\n", "convert the provided text to speech", "<|im_end|>\n",
      "<|im_start|>user\n", content, "<|im_end|>\n", "<|im_start|>assistant\n<|voice|>",
    ]
    let tokens = segments.flatMap { tokenizer.encode(text: $0, addSpecialTokens: false) }
    guard !tokens.isEmpty, tokens.count <= FishConfiguration.maximumPromptTokens,
      tokens.allSatisfy({ $0 >= 0 && $0 < configuration.textConfig.vocabSize })
    else { throw FishError.invalidTokenizer }
    return tokens.map(Int32.init)
  }
}
