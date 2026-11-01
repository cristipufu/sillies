import Foundation
import SilliesCore
import SilliesTTS

/// Owns the output device. Native buffers and hardware setup never escape this actor.
package actor VoicePlayback: SpeechPlayback {
  private struct Pending {
    let seconds: Double
    let level: Double
  }
  private static let maximumQueuedSeconds = 0.75
  private static let meterGain = 4.0
  private let makeDevice: @Sendable () -> any VoiceOutputDevice
  private var device: (any VoiceOutputDevice)?
  private var generation = UUID()
  private var currentID: UUID?
  private var receive: (@Sendable (SpeechPlaybackUpdate) -> Void)?
  private var pending: [Pending] = []
  private var queuedSeconds = 0.0
  private var capacityWaiter: CheckedContinuation<Void, Error>?
  private var finishWaiter: CheckedContinuation<Void, Error>?

  package init(reference: (@Sendable (AudioRenderFrame) -> Void)? = nil) {
    makeDevice = { NativeVoiceOutput(reference: reference) }
  }
  package init(makeDevice: @escaping @Sendable () -> any VoiceOutputDevice) {
    self.makeDevice = makeDevice
  }

  package func start(id: UUID, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void) {
    reset()
    currentID = id
    self.receive = receive
  }

  package func enqueue(_ audio: SynthesizedAudio, id: UUID) async throws {
    try audio.validate()
    let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard currentID == id else { throw CancellationError() }
      while queuedSeconds + seconds > Self.maximumQueuedSeconds {
        guard capacityWaiter == nil else { throw TTSError.busy }
        try await withCheckedThrowingContinuation { capacityWaiter = $0 }
        try Task.checkCancellation()
        guard currentID == id else { throw CancellationError() }
      }
      try schedule(audio, id: id, seconds: seconds)
    } onCancel: {
      Task { await self.stop(id: id) }
    }
  }

  package func finish(id: UUID) async throws {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard currentID == id else { throw CancellationError() }
      if !pending.isEmpty {
        guard finishWaiter == nil else { throw TTSError.busy }
        try await withCheckedThrowingContinuation { finishWaiter = $0 }
      }
      guard currentID == id else { throw CancellationError() }
      reset()
    } onCancel: {
      Task { await self.stop(id: id) }
    }
  }

  package func stop(id: UUID) {
    guard currentID == id else { return }
    reset()
  }

  private func schedule(_ audio: SynthesizedAudio, id: UUID, seconds: Double) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let device = device ?? makeDevice()
    self.device = device
    let power =
      audio.samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(audio.samples.count)
    let level = min(1, sqrt(power) * Self.meterGain)
    pending.append(.init(seconds: seconds, level: level))
    queuedSeconds += seconds
    let token = generation
    do {
      try device.schedule(audio) { [weak self] in
        Task { await self?.completed(id: id, generation: token) }
      }
    } catch {
      reset()
      throw error
    }
    if pending.count == 1 { receive?(.speaking(level: level)) }
  }

  private func completed(id: UUID, generation token: UUID) {
    guard currentID == id, generation == token, !pending.isEmpty else { return }
    queuedSeconds = max(0, queuedSeconds - pending.removeFirst().seconds)
    let capacity = capacityWaiter
    capacityWaiter = nil
    capacity?.resume()
    if let next = pending.first {
      receive?(.speaking(level: next.level))
    } else {
      receive?(.finished)
      let finish = finishWaiter
      finishWaiter = nil
      finish?.resume()
    }
  }

  private func reset() {
    currentID = nil
    generation = UUID()
    device?.stop()
    device = nil
    pending.removeAll()
    queuedSeconds = 0
    capacityWaiter?.resume(throwing: CancellationError())
    finishWaiter?.resume(throwing: CancellationError())
    capacityWaiter = nil
    finishWaiter = nil
    receive?(.finished)
    receive = nil
  }
}
