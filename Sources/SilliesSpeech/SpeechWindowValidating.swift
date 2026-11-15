/// Acoustic confirmation on the speech worker before a provider receives audio.
package protocol SpeechWindowValidating: Sendable {
  func containsSpeech(_ samples: [Float]) async throws -> Bool
}

package typealias SpeechWindowValidatorFactory = @Sendable () throws -> any SpeechWindowValidating
