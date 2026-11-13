import Foundation
import SilliesCore
import Synchronization

/// Selects once at startup. Only unsupported tap configurations permit ScreenCaptureKit fallback.
actor ApplicationAudioSource: ApplicationCapture {
  struct Providers: Sendable {
    typealias Make =
      @Sendable (
        @escaping AudioCaptureInputQueue.Receiver, @escaping ApplicationAudioRequest.Failure
      ) ->
      any ApplicationCapture
    let preferred: Make
    let fallback: Make
  }
  private enum Phase { case idle, starting, active, stopping, stopped }
  private let providers: Providers
  private let failure: ApplicationAudioRequest.Failure
  private let delivery: ApplicationAudioDelivery
  nonisolated private let commands = Mutex<Task<Void, Never>?>(nil)
  private enum Command: Sendable {
    case pause, resume
    case stop(@Sendable (SessionFailure?) -> Void)
  }
  private var phase = Phase.idle
  private var stopOutcome: SessionFailure?
  private var current: (any ApplicationCapture)?
  private var generation = UUID()
  private var completions: [@Sendable (SessionFailure?) -> Void] = []

  init(
    providers: Providers, receive: @escaping AudioCaptureInputQueue.Receiver,
    failure: @escaping ApplicationAudioRequest.Failure
  ) {
    self.providers = providers
    self.failure = failure
    delivery = ApplicationAudioDelivery(receive: receive)
  }
  init(request: ApplicationAudioRequest, identity: @escaping ApplicationAudioIdentityCheck) {
    self.init(
      providers: .init(
        preferred: { receive, failure in
          CoreAudioApplicationCapture(
            request: .init(target: request.target, receive: receive, failure: failure),
            identity: identity)
        },
        fallback: { receive, failure in
          ScreenCaptureKitApplicationCapture(
            target: request.target, receive: receive, failure: failure)
        }), receive: request.receive, failure: request.failure)
  }

  func start() async throws {
    guard phase == .idle else { throw CancellationError() }
    phase = .starting
    do {
      try await withTaskCancellationHandler {
        try await selectAndStartProvider()
        try ensureStarting()
        phase = .active
      } onCancel: {
        self.stop { _ in }
      }
    } catch {
      await stopOwnedProvider { _ in }
      throw error
    }
  }
  private func selectAndStartProvider() async throws {
    do {
      try await startProvider(providers.preferred)
    } catch CoreAudioCaptureError.unsupported {
      delivery.stop()
      generation = UUID()
      let cleanup = await stopCurrent()
      if let cleanup { throw cleanup }
      try ensureStarting()
      try await startProvider(providers.fallback)
    }
  }
  private func startProvider(_ make: Providers.Make) async throws {
    try ensureStarting()
    let token = UUID()
    generation = token
    delivery.select(token)
    let provider = make(
      { [delivery] in delivery.receive($0, from: token) },
      { [weak self] failure in
        Task { await self?.receiveFailure(failure, from: token) }
      })
    current = provider
    try await provider.start()
    try ensureStarting()
  }
  private func ensureStarting() throws {
    guard phase == .starting, !Task.isCancelled else { throw CancellationError() }
  }
  private func receiveFailure(_ event: SessionFailure, from token: UUID) {
    guard token == generation, phase == .starting || phase == .active else { return }
    failure(event)
  }
  nonisolated func pause() { enqueue(.pause) }
  nonisolated func resume() { enqueue(.resume) }
  nonisolated func stop(completion: @escaping @Sendable (SessionFailure?) -> Void) {
    enqueue(.stop(completion))
  }
  nonisolated private func enqueue(_ command: Command) {
    commands.withLock { tail in
      let preceding = tail
      tail = Task { [self] in
        await preceding?.value
        await apply(command)
      }
    }
  }
  private func apply(_ command: Command) async {
    switch command {
    case .pause: if phase == .active { current?.pause() }
    case .resume: if phase == .active { current?.resume() }
    case .stop(let completion): await stopOwnedProvider(completion)
    }
  }
  private func stopOwnedProvider(_ completion: @escaping @Sendable (SessionFailure?) -> Void) async
  {
    if phase == .stopped {
      completion(stopOutcome)
      return
    }
    completions.append(completion)
    guard phase != .stopping else { return }
    phase = .stopping
    generation = UUID()
    delivery.stop()
    let outcome = await stopCurrent()
    current = nil
    stopOutcome = outcome
    phase = .stopped
    let pending = completions
    completions.removeAll()
    for completion in pending { completion(outcome) }
  }
  private func stopCurrent() async -> SessionFailure? {
    guard let current else { return nil }
    return await withCheckedContinuation { continuation in
      let completed = Mutex(false)
      current.stop { result in
        let first = completed.withLock { flag in
          if flag { return false }
          flag = true
          return true
        }
        if first { continuation.resume(returning: result) }
      }
    }
  }
}
