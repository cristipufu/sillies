import Foundation
import SilliesSpeech

/// Warming weights is finite work. A recognizer reserves interactive priority only for an utterance.
package struct ConversationSpeechServices: Sendable {
  package let warm: @Sendable () async throws -> Void
  package let makeChannel: LocalSpeechFactory.Make
  package init(
    warm: @escaping @Sendable () async throws -> Void,
    makeChannel: @escaping LocalSpeechFactory.Make
  ) {
    self.warm = warm
    self.makeChannel = makeChannel
  }
}
