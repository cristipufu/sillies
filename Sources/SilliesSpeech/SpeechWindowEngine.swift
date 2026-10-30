import Foundation

package struct SpeechWord: Sendable, Equatable {
  package enum Boundary: Sendable { case separated, attached }
  package let text: String
  package let start: TimeInterval
  package let end: TimeInterval
  package let boundary: Boundary
  package init(
    text: String, start: TimeInterval, end: TimeInterval, boundary: Boundary = .separated
  ) {
    self.text = text
    self.start = start
    self.end = end
    self.boundary = boundary
  }

  package static func renderedText(_ words: [Self]) -> String {
    words.reduce(into: "") { text, word in
      if !text.isEmpty, word.boundary == .separated { text += " " }
      text += word.text
    }.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

package struct SpeechWindowRequest: Sendable {
  package let samples: [Float]
  package let language: SpeechLanguage
  package init(samples: [Float], language: SpeechLanguage) {
    self.samples = samples
    self.language = language
  }
}

package struct SpeechWindowResult: Sendable {
  package let words: [SpeechWord]
  package let detectedLanguage: String?
  package init(words: [SpeechWord], detectedLanguage: String? = nil) {
    self.words = words
    self.detectedLanguage = detectedLanguage
  }
}

package protocol SpeechWindowEngine: Sendable {
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult
}
