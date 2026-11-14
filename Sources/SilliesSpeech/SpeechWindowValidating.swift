/// Optional acoustic confirmation before a provider receives newly eligible short audio.
package protocol SpeechWindowValidating: Sendable {
  func containsSpeech(_ samples: [Float]) throws -> Bool
}

package typealias SpeechWindowValidatorFactory = @Sendable () throws -> any SpeechWindowValidating
