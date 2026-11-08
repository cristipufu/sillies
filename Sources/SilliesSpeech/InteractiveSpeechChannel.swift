import AVFoundation
import Foundation
import SilliesInference

/// Reserves resources through capture and finalization, including Apple's streaming recognizer.
package final class InteractiveSpeechChannel: LocalSpeechChannel {
  private let base: any LocalSpeechChannel
  private let reservation: SpeechReservation

  init(base: any LocalSpeechChannel, reservation: SpeechReservation) {
    self.base = base
    self.reservation = reservation
  }
  package static func make(
    activity: InferenceActivity = .shared,
    _ create: @Sendable () async throws -> any LocalSpeechChannel
  ) async throws -> any LocalSpeechChannel {
    try Task.checkCancellation()
    await activity.beginSpeech()
    let reservation = SpeechReservation { await activity.endSpeech() }
    do {
      try Task.checkCancellation()
      let base = try await create()
      guard !Task.isCancelled else {
        base.cancel()
        throw CancellationError()
      }
      return InteractiveSpeechChannel(base: base, reservation: reservation)
    } catch {
      await reservation.release().value
      throw error
    }
  }
  package func append(_ buffer: AVAudioPCMBuffer) { base.append(buffer) }
  package func finish(completion: @escaping @Sendable () -> Void) {
    base.finish { [reservation] in
      let release = reservation.release()
      Task {
        await release.value
        completion()
      }
    }
  }
  package func cancel() {
    base.cancel()
    reservation.release()
  }
  deinit { reservation.release() }
}
