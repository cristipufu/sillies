import Foundation

package enum FishError: LocalizedError {
  case unsupportedConfiguration
  case invalidTensor(String)
  case invalidTokenizer
  case generationLimit
  case emptyAudio

  package var errorDescription: String? {
    switch self {
    case .unsupportedConfiguration:
      String(
        localized: "This Fish model configuration is not supported by this version of Sillies.")
    case .invalidTensor(let name):
      String(localized: "The Fish model has an incompatible tensor: \(name). Reinstall the model.")
    case .invalidTokenizer:
      String(localized: "The Fish tokenizer is incompatible with the installed model.")
    case .generationLimit:
      String(
        localized:
          "Fish could not finish this passage within its generation limit. Try a shorter passage.")
    case .emptyAudio:
      String(
        localized: "Fish finished without producing speech. Your reply is still available as text.")
    }
  }
}
