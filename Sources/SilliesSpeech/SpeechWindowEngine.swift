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
  package let context: SpeechRecognitionContext
  package var window: SpeechWindowPosition?
  package init(
    samples: [Float], language: SpeechLanguage, context: SpeechRecognitionContext = .init()
  ) {
    self.samples = samples
    self.language = language
    self.context = context
  }
}

/// Identifies a bounded utterance so streaming engines can decode only newly appended audio.
package struct SpeechWindowPosition: Sendable {
  package enum Phase: String, Codable, Sendable { case partial, complete }
  package let start: TimeInterval
  package let phase: Phase
  package init(start: TimeInterval, phase: Phase) {
    self.start = start
    self.phase = phase
  }
}

package enum SpeechDecodeCadence: Sendable {
  case windowed, streaming
  var interval: TimeInterval {
    switch self {
    case .windowed: 2
    case .streaming: 0.56
    }
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
  var finalizationPolicy: SpeechFinalizationPolicy { get }
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult
}

extension SpeechWindowEngine {
  package var finalizationPolicy: SpeechFinalizationPolicy { .decode }
}
