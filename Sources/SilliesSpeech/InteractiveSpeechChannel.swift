import AVFoundation
import Foundation
import SilliesInference
import Synchronization

/// Reserves resources through capture and finalization, including Apple's streaming recognizer.
package final class InteractiveSpeechChannel: LocalSpeechChannel {
  private let base: any LocalSpeechChannel
  private let reservation: SpeechReservation

  private init(base: any LocalSpeechChannel, reservation: SpeechReservation) {
    self.base = base
    self.reservation = reservation
  }
  package static func make(
    _ create: @Sendable () async throws -> any LocalSpeechChannel
  ) async throws -> any LocalSpeechChannel {
    await InferenceActivity.shared.beginSpeech()
    let reservation = SpeechReservation()
    do {
      try Task.checkCancellation()
      let base = try await create()
      guard !Task.isCancelled else {
        base.cancel()
        throw CancellationError()
      }
      return InteractiveSpeechChannel(base: base, reservation: reservation)
    } catch {
      reservation.release()
      throw error
    }
  }
  package func append(_ buffer: AVAudioPCMBuffer) { base.append(buffer) }
  package func finish(completion: @escaping @Sendable () -> Void) {
    base.finish { [reservation] in
      reservation.release()
      completion()
    }
  }
  package func cancel() {
    base.cancel()
    reservation.release()
  }
  deinit { reservation.release() }
}

private final class SpeechReservation: Sendable {
  private let released = Mutex(false)
  func release() {
    let shouldRelease = released.withLock { released in
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { Task { await InferenceActivity.shared.endSpeech() } }
  }
}
