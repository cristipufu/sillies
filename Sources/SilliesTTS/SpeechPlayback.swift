import Foundation

package enum SpeechPlaybackUpdate: Sendable {
  case speaking(level: Double)
  case finished
}

package protocol SpeechPlayback: Sendable {
  func start(id: UUID, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void) async
  func enqueue(_ audio: SynthesizedAudio, id: UUID) async throws
  func finish(id: UUID) async throws
  func stop(id: UUID) async
}
