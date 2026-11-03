import Foundation
import SilliesTextModels

/// Reviewed publisher templates shipped with the adapter, without changing downloaded artifacts.
enum NativeChatTemplate {
  static func load(_ policy: TextModelPreparation.RuntimePolicy.ChatTemplate) throws -> String? {
    switch policy {
    case .checkpoint: return nil
    case .mistral3:
      guard
        let url = Bundle.module.url(
          forResource: "mistral3", withExtension: "jinja", subdirectory: "Resources")
      else { throw TextModelError.invalidResponse }
      return try String(contentsOf: url, encoding: .utf8)
    }
  }
}
