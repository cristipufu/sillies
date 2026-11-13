import CoreAudio
import Foundation
import SilliesCore
import Synchronization

/// Native state is confined to one worker. A separate gate stops packet delivery immediately.
final class CoreAudioApplicationCapture: ApplicationCapture {
  private enum Intent { case recording, paused, stopped }
  private struct Control {
    var intent = Intent.recording
    var emitter: CoreAudioPacketEmitter?
  }
  private final class State {
    enum Phase { case idle, recording, paused, stopped }
    let system: any CoreAudioTapSystem
    let resources: CoreAudioTapResources
    var phase = Phase.idle
    var generation = UUID()
    var selection: CoreAudioTapSelection?
    var emitter: CoreAudioPacketEmitter?
    init(system: any CoreAudioTapSystem) {
      self.system = system
      resources = .init(system: system)
    }
  }
  private let request: ApplicationAudioRequest
  private let identity: ApplicationAudioIdentityCheck
  private let queue: DispatchQueue
  private let storage: SerialQueueStorage<State>
  private let control = Mutex(Control())

  init(
    request: ApplicationAudioRequest, identity: @escaping ApplicationAudioIdentityCheck,
    makeSystem: @Sendable () -> any CoreAudioTapSystem = { NativeCoreAudioTapSystem() }
  ) {
    let queue = DispatchQueue(label: "app.sillies.core-audio-capture", qos: .userInitiated)
    self.queue = queue
    self.request = request
    self.identity = identity
    storage = SerialQueueStorage(queue: queue, makeValue: { State(system: makeSystem()) })
  }

  func start() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        queue.async { [self] in
          guard storage.withValue({ $0.phase == .idle }) else {
            continuation.resume(throwing: CancellationError())
            return
          }
          do {
            try storage.withValue { state in
              guard state.phase == .idle, wantsRecording else { throw CancellationError() }
              try prepare(state)
            }
            continuation.resume()
          } catch {
            storage.withValue { state in
              state.phase = .stopped
              // Cleanup reports its own fault and retains failed handles for stop to retry.
              _ = cleanup(state)
            }
            continuation.resume(throwing: startupFailure(error))
          }
        }
      }
    } onCancel: {
      self.stop { _ in }
    }
  }
  private var wantsRecording: Bool { control.withLock { $0.intent == .recording } }
  private func verifiedSelection(_ state: State) throws -> CoreAudioTapSelection {
    switch identity(request.target) {
    case .ambiguous: throw CoreAudioCaptureError.unsupported
    case .unavailable:
      throw AudioCaptureFailure.unavailable(
        String(localized: "The selected application is no longer available."))
    case .verified: return try state.system.selection(for: request.target)
    }
  }
  private func prepare(_ state: State) throws {
    guard wantsRecording else { throw CancellationError() }
    let selection = try verifiedSelection(state)
    let format = try state.resources.prepare(selection)
    let generation = UUID()
    state.generation = generation
    let emitter = try CoreAudioPacketEmitter(format: format, receive: request.receive) {
      [weak self] error in
      self?.queue.async { [weak self] in self?.fail(error, generation: generation) }
    }
    state.emitter = emitter
    control.withLock { control in
      control.emitter = emitter
      if control.intent != .recording { emitter.stop() }
    }
    guard wantsRecording else { throw CancellationError() }
    let changes = CoreAudioChangeDelivery(queue: queue) { [weak self] signal in
      self?.refresh(signal, generation: generation)
    }
    try state.resources.start(
      receive: { [self, emitter] input, timestamp in
        // The registered IOProc retains its owner until native teardown has drained callbacks.
        withExtendedLifetime(self) { emitter.receive(input, at: timestamp) }
      },
      changed: { change in
        if let ticket = emitter.suspend() { changes.send(.init(change: change, ticket: ticket)) }
      }, output: selection.output.id)
    guard wantsRecording else { throw CancellationError() }
    state.selection = selection
    state.phase = .recording
  }
  private func refresh(_ signal: CoreAudioChangeDelivery.Signal, generation: UUID) {
    let failure = storage.withValue { state -> SessionFailure? in
      guard state.phase == .recording, state.generation == generation, wantsRecording else {
        return nil
      }
      do {
        let selection = try verifiedSelection(state)
        if signal.change == .processes, selection == state.selection {
          state.emitter?.resume(signal.ticket)
          return nil
        }
        if let error = cleanup(state) {
          state.phase = .stopped
          return error.failure(category: .captureInterrupted)
        }
        try prepare(state)
        return nil
      } catch {
        let cleanupFailure = cleanup(state)
        state.phase = .stopped
        return cleanupFailure?.failure(category: .finalization) ?? runtimeFailure(error)
      }
    }
    if let failure { request.failure(failure) }
  }
  private func fail(_ error: CoreAudioCaptureError, generation: UUID) {
    let failure = storage.withValue { state -> SessionFailure? in
      guard state.phase == .recording, state.generation == generation else { return nil }
      let cleanupFailure = cleanup(state)
      state.phase = .stopped
      return (cleanupFailure ?? error).failure(category: .audioProcessing)
    }
    if let failure { request.failure(failure) }
  }
  private func cleanup(_ state: State) -> CoreAudioCaptureError? {
    state.generation = UUID()
    state.emitter?.stop()
    control.withLock { $0.emitter = nil }
    state.emitter = nil
    state.selection = nil
    return state.resources.release()
  }
  func pause() {
    let emitter = control.withLock { control -> CoreAudioPacketEmitter? in
      guard control.intent != .stopped else { return nil }
      control.intent = .paused
      return control.emitter
    }
    emitter?.stop()
    queue.async { [self] in
      let failure = storage.withValue { state -> SessionFailure? in
        guard state.phase == .recording else { return nil }
        let failure = cleanup(state)?.failure(category: .captureInterrupted)
        state.phase = failure == nil ? .paused : .stopped
        return failure
      }
      if let failure { request.failure(failure) }
    }
  }
  func resume() {
    let accepted = control.withLock { control in
      guard control.intent != .stopped else { return false }
      control.intent = .recording
      return true
    }
    guard accepted else { return }
    queue.async { [self] in
      let failure = storage.withValue { state -> SessionFailure? in
        guard state.phase == .paused, wantsRecording else { return nil }
        do {
          try prepare(state)
          return nil
        } catch {
          let cleanupFailure = cleanup(state)
          state.phase = .stopped
          return cleanupFailure?.failure(category: .finalization) ?? runtimeFailure(error)
        }
      }
      if let failure { request.failure(failure) }
    }
  }
  func stop(completion: @escaping @Sendable (SessionFailure?) -> Void) {
    let emitter = control.withLock { control in
      control.intent = .stopped
      return control.emitter
    }
    emitter?.stop()
    queue.async { [self] in
      let result = storage.withValue { state in
        state.phase = .stopped
        return cleanup(state)?.failure(category: .finalization)
      }
      completion(result)
    }
  }
  private func startupFailure(_ error: Error) -> Error {
    guard let native = error as? CoreAudioCaptureError else { return error }
    if case .unsupported = native { return native }
    if case .native(_, let status) = native,
      status == kAudioHardwareUnsupportedOperationError
        || status == kAudioDeviceUnsupportedFormatError
    {
      return CoreAudioCaptureError.unsupported
    }
    return native.failure(category: .captureUnavailable)
  }
  private func runtimeFailure(_ error: Error) -> SessionFailure {
    if let native = error as? CoreAudioCaptureError {
      return native.failure(category: .captureInterrupted)
    }
    return SessionFailure(error, category: .captureInterrupted)
  }
}
