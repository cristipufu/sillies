import AVFoundation
import Foundation
import SilliesCore

package struct SpeechPhrase: Sendable {
  package var text: String
  package let isFinal: Bool
  package var startTime: TimeInterval?
  package var duration: TimeInterval?
  package var finalizedThrough: TimeInterval?
  package var words: [SpeechWord] = []
  package var speaker: TranscriptSpeaker?

  package init(
    text: String, isFinal: Bool, startTime: TimeInterval? = nil, duration: TimeInterval? = nil,
    finalizedThrough: TimeInterval? = nil
  ) {
    self.text = text
    self.isFinal = isFinal
    self.startTime = startTime
    self.duration = duration
    self.finalizedThrough = finalizedThrough
  }

  package func shifted(by offset: TimeInterval) -> SpeechPhrase {
    var phrase = self
    phrase.startTime = startTime.map { $0 + offset }
    phrase.finalizedThrough = finalizedThrough.map { $0 + offset }
    phrase.words = words.map {
      SpeechWord(
        text: $0.text, start: $0.start + offset, end: $0.end + offset, boundary: $0.boundary)
    }
    return phrase
  }
}

package protocol LocalSpeechChannel: AnyObject, Sendable {
  func append(_ buffer: AVAudioPCMBuffer)
  func finish(completion: @escaping @Sendable () -> Void)
  func cancel()
}

package enum LocalSpeechFactory {
  package typealias Output = @Sendable (SpeechPhrase) -> Void
  package typealias Failure = @Sendable (String) -> Void
  package typealias Make =
    @Sendable (SpeechLanguage, @escaping Output, @escaping Failure) async throws ->
    any LocalSpeechChannel

}
