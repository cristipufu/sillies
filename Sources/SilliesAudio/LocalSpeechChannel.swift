import AVFoundation
import Foundation

struct SpeechPhrase: Sendable {
  let text: String
  let isFinal: Bool
  var startTime: TimeInterval?
  var duration: TimeInterval?
  var finalizedThrough: TimeInterval?

  func shifted(by offset: TimeInterval) -> SpeechPhrase {
    var phrase = self
    phrase.startTime = startTime.map { $0 + offset }
    phrase.finalizedThrough = finalizedThrough.map { $0 + offset }
    return phrase
  }
}

protocol LocalSpeechChannel: AnyObject, Sendable {
  func append(_ buffer: AVAudioPCMBuffer)
  func finish(completion: @escaping @Sendable () -> Void)
  func cancel()
}

enum LocalSpeechFactory {
  typealias Output = @Sendable (SpeechPhrase) -> Void
  typealias Failure = @Sendable (String) -> Void
  typealias Make =
    @Sendable (SpeechLanguage, @escaping Output, @escaping Failure) async throws ->
    any LocalSpeechChannel

  static func make(language: SpeechLanguage, output: @escaping Output, failure: @escaping Failure)
    async throws
    -> any LocalSpeechChannel
  {
    guard language.isInstalled else {
      throw AudioCaptureFailure.unavailable(
        "The Apple speech model for \(language.name) is not installed. Choose a language marked Ready on this Mac."
      )
    }
    return try await AnalyzerSpeechChannel.make(
      locale: language.locale, output: output, failure: failure)
  }
}
