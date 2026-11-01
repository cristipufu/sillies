import Foundation
import SilliesCore
import SilliesTTS

/// Owns the output device. Native buffers and hardware setup never escape this actor.
package actor VoicePlayback: SpeechPlayback {
  private struct Pending {
    let id = UUID()
    var completed = false
    let seconds: Double
    let level: Double
    var utterances: [String] = []
  }
  private static let maximumQueuedSeconds = 0.75
  private static let meterGain = 4.0
  private let makeDevice: @Sendable () -> any VoiceOutputDevice
  private let stallTimeout: Duration
  private var watchdog: Task<Void, Never>?
  private var lastProgress = ContinuousClock.now
  private var failedID: UUID?
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
    stallTimeout = .seconds(3)
  }
  package init(
    makeDevice: @escaping @Sendable () -> any VoiceOutputDevice,
    stallTimeout: Duration = .seconds(3)
  ) {
    self.makeDevice = makeDevice
    self.stallTimeout = stallTimeout
  }

  package func start(id: UUID, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void) {
    reset()
    failedID = nil
    currentID = id
    self.receive = receive
  }

  package func enqueue(_ audio: SynthesizedAudio, id: UUID) async throws {
    try audio.validate()
    let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try requireSession(id)
      while queuedSeconds + seconds > Self.maximumQueuedSeconds {
        guard capacityWaiter == nil else { throw TTSError.busy }
        try await withCheckedThrowingContinuation { capacityWaiter = $0 }
        try Task.checkCancellation()
        try requireSession(id)
      }
      try schedule(audio, id: id, seconds: seconds)
    } onCancel: {
      Task { await self.stop(id: id) }
    }
  }

  package func prepare(sampleRate: Int, id: UUID) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    try requireSession(id)
    do { try outputDevice(id: id).prepare(sampleRate: sampleRate) } catch {
      reset()
      throw error
    }
  }

  package func finish(id: UUID) async throws {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try requireSession(id)
      if !pending.isEmpty {
        guard finishWaiter == nil else { throw TTSError.busy }
        try await withCheckedThrowingContinuation { finishWaiter = $0 }
      }
      try requireSession(id)
      reset()
    } onCancel: {
      Task { await self.stop(id: id) }
    }
  }

  package func stop(id: UUID) {
    guard currentID == id else { return }
    reset()
  }

  package func markUtterance(_ text: String, id: UUID) throws {
    try Task.checkCancellation()
    try requireSession(id)
    if pending.isEmpty {
      receive?(.utteranceFinished(text))
    } else {
      pending[pending.count - 1].utterances.append(text)
    }
  }

  private func schedule(_ audio: SynthesizedAudio, id: UUID, seconds: Double) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let device = outputDevice(id: id)
    let token = generation
    let power =
      audio.samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(audio.samples.count)
    let level = min(1, sqrt(power) * Self.meterGain)
    let buffer = Pending(seconds: seconds, level: level)
    if pending.isEmpty { lastProgress = .now }
    pending.append(buffer)
    queuedSeconds += seconds
    do {
      try device.schedule(audio) { [weak self] in
        Task { await self?.completed(id: id, generation: token, buffer: buffer.id) }
      }
    } catch {
      reset()
      throw error
    }
    watchProgress(id: id, generation: token)
    if pending.count == 1 { receive?(.speaking(level: level)) }
  }

  private func outputDevice(id: UUID) -> any VoiceOutputDevice {
    if let device { return device }
    let device = makeDevice()
    let token = generation
    device.onInterruption { [weak self] in
      Task { await self?.outputInterrupted(id: id, generation: token) }
    }
    device.onAudibleOutput { [weak self] time in
      Task { await self?.audibleOutput(time, id: id, generation: token) }
    }
    self.device = device
    return device
  }

  private func completed(id: UUID, generation token: UUID, buffer: UUID) {
    guard currentID == id, generation == token,
      let index = pending.firstIndex(where: { $0.id == buffer }), !pending[index].completed
    else { return }
    pending[index].completed = true
    lastProgress = .now
    guard pending.first?.completed == true else { return }
    while pending.first?.completed == true {
      let completed = pending.removeFirst()
      queuedSeconds = max(0, queuedSeconds - completed.seconds)
      for text in completed.utterances { receive?(.utteranceFinished(text)) }
    }
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

  private func requireSession(_ id: UUID) throws {
    if failedID == id { throw TTSError.interrupted }
    guard currentID == id else { throw CancellationError() }
  }

  private func audibleOutput(_ time: TimeInterval, id: UUID, generation token: UUID) {
    guard currentID == id, generation == token else { return }
    receive?(.milestone(.audibleOutput(time)))
  }

  private func outputInterrupted(id: UUID, generation token: UUID) {
    guard currentID == id, generation == token else { return }
    failedID = id
    let notify = receive
    reset(throwing: TTSError.interrupted)
    notify?(.interrupted)
  }

  private func watchProgress(id: UUID, generation token: UUID) {
    guard watchdog == nil else { return }
    let timeout = stallTimeout
    watchdog = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: timeout) } catch { return }
        guard let self, await self.checkProgress(id: id, generation: token) else { return }
      }
    }
  }

  private func checkProgress(id: UUID, generation token: UUID) -> Bool {
    guard currentID == id, generation == token else { return false }
    if !pending.isEmpty, lastProgress.duration(to: .now) >= stallTimeout {
      outputInterrupted(id: id, generation: token)
      return false
    }
    return true
  }

  private func reset(throwing error: any Error = CancellationError()) {
    watchdog?.cancel()
    watchdog = nil
    currentID = nil
    generation = UUID()
    device?.stop()
    device = nil
    pending.removeAll()
    queuedSeconds = 0
    capacityWaiter?.resume(throwing: error)
    finishWaiter?.resume(throwing: error)
    capacityWaiter = nil
    finishWaiter = nil
    receive?(.finished)
    receive = nil
  }
}
