import Foundation

/// Reusable voice conditioning is independent of the text of an individual phrase.
package struct SpeechVoice: Codable, Sendable, Equatable {
  private static let maximumIDBytes = 128
  private static let maximumLanguageBytes = 64
  package let id: String
  package let language: String

  package init(id: String, language: String) {
    self.id = id
    self.language = language
  }

  package func validate() throws {
    guard !id.isEmpty, id.utf8.count <= Self.maximumIDBytes,
      !language.isEmpty, language.utf8.count <= Self.maximumLanguageBytes
    else {
      throw TTSError.invalidRequest
    }
  }
}
