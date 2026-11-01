import Foundation

package enum SpeechDeliveryMilestone: Sendable {
  case phraseReady, preparationStarted, voicePrepared, firstPCM
  case audibleOutput(TimeInterval)
}

package enum SpeechPlaybackUpdate: Sendable {
  case speaking(level: Double)
  case finished
  case interrupted
  case utteranceFinished(String)
  case milestone(SpeechDeliveryMilestone)
}

package protocol SpeechPlayback: Sendable {
  func start(id: UUID, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void) async
  func prepare(sampleRate: Int, id: UUID) async throws
  func enqueue(_ audio: SynthesizedAudio, id: UUID) async throws
  func finish(id: UUID) async throws
  func stop(id: UUID) async
  func markUtterance(_ text: String, id: UUID) async throws
}
