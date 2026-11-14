import SilliesSpeech

/// A source's native decoder consumes only newly prepared samples and flushes on completion.
protocol NemotronDecoding: Sendable {
  func decode(_ samples: [Float], phase: SpeechWindowPosition.Phase) async throws
    -> SpeechWindowResult
  func reset() async throws
}
