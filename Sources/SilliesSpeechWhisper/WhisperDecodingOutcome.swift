import Foundation
import SilliesSpeech
import WhisperKit

/// Existing windows retain native results; newly decoded short windows must meet native confidence limits.
struct WhisperDecodingOutcome: Sendable {
  let nativeResults: [TranscriptionResult]
  let context: WhisperTranscriptionInput.Context
  let options: DecodingOptions

  var acceptedSegments: [TranscriptionSegment] {
    nativeResults.flatMap(\.segments).filter(accepts)
  }

  var result: SpeechWindowResult {
    .init(
      words: acceptedSegments.flatMap { segment in
        (segment.words ?? []).map {
          .init(
            text: $0.word.trimmingCharacters(in: .whitespaces), start: Double($0.start),
            end: Double($0.end),
            boundary: $0.word.first?.isWhitespace == true ? .separated : .attached)
        }
      }, detectedLanguage: nativeResults.first?.language)
  }

  private func accepts(_ segment: TranscriptionSegment) -> Bool {
    guard context == .extended else { return true }
    guard segment.avgLogprob.isFinite, segment.compressionRatio.isFinite else { return false }
    if let minimum = options.logProbThreshold, segment.avgLogprob < minimum { return false }
    if let maximum = options.compressionRatioThreshold, segment.compressionRatio > maximum {
      return false
    }
    return true
  }
}
