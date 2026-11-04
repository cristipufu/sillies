import Foundation
import SilliesCore
import SilliesInference

/// A single helper owns one immutable model. Admission, cancellation and eviction are explicit.
package actor EmbeddingWorkerSession {
  private static let preparationTimeout: TimeInterval = 45
  private static let queryTimeout: TimeInterval = 2
  private static let passageTimeout: TimeInterval = 15
  private let executable: URL
  private let configuration: EmbeddingConfiguration
  private let activity: InferenceActivity
  private let reservation: InferenceReservation
  private let residencyID = UUID()
  private var worker: InferenceWorkerConnection?
  private var identity: String?
  private var operation: Task<EmbeddingResponse, any Error>?
  var isBusy: Bool { operation != nil }
  private var stopped = false
  private var warming: Task<Void, Never>?

  package init(
    configuration: EmbeddingConfiguration, executable: URL,
    modelBytes: Int64, activity: InferenceActivity
  ) {
    self.configuration = configuration
    self.executable = executable
    self.activity = activity
    reservation = .init(modelBytes: modelBytes)
  }

  package func access() async throws -> MemoryEmbeddingAccess {
    _ = try await exchange(.prepare(configuration), timeout: Self.preparationTimeout)
    guard let identity else { throw MemoryEmbeddingError.unavailable }
    return .init(
      identity: identity,
      embed: { [weak self] input in
        guard let self else { throw CancellationError() }
        return try await self.embed(input)
      })
  }

  private func embed(_ input: MemoryEmbeddingInput) async throws -> MemoryEmbedding? {
    // Interactive queries use keywords if a model is cold or its worker is occupied.
    if input.purpose == .query, worker == nil || isBusy {
      if worker == nil, !isBusy, !stopped { warmInBackground() }
      throw MemoryEmbeddingError.unavailable
    }
    if input.purpose == .passage, let warming {
      await withTaskCancellationHandler {
        await warming.value
      } onCancel: {
        warming.cancel()
      }
      try Task.checkCancellation()
    }
    let timeout = input.purpose == .query ? Self.queryTimeout : Self.passageTimeout
    return try await exchange(.embed(input), timeout: timeout).embedding
  }

  private func exchange(_ request: EmbeddingRequest, timeout: TimeInterval) async throws
    -> EmbeddingResponse
  {
    guard !stopped else { throw CancellationError() }
    guard !isBusy else { throw MemoryEmbeddingError.unavailable }
    let pending = Task { try await admittedExchange(request, timeout: timeout) }
    operation = pending
    defer { operation = nil }
    return try await withTaskCancellationHandler {
      try await pending.value
    } onCancel: {
      pending.cancel()
    }
  }

  private func admittedExchange(_ request: EmbeddingRequest, timeout: TimeInterval) async throws
    -> EmbeddingResponse
  {
    let priority: InferenceActivity.EmbeddingPriority
    if case .embed(let input) = request, input.purpose == .query {
      priority = .query
    } else {
      priority = .background
    }
    while true {
      try Task.checkCancellation()
      let id = UUID()
      let cancellation = InferenceCancellation()
      guard await activity.claimEmbedding(id, priority: priority, cancel: { cancellation.cancel() })
      else {
        if case .embed(let input) = request, input.purpose == .query {
          throw MemoryEmbeddingError.unavailable
        }
        try await activity.waitForEmbeddingAdmission(priority)
        continue
      }
      let task = Task { try await perform(request, timeout: timeout) }
      cancellation.install { task.cancel() }
      do {
        let response = try await withTaskCancellationHandler {
          try await task.value
        } onCancel: {
          task.cancel()
        }
        await activity.releaseEmbedding(id)
        return response
      } catch {
        await evict()
        await activity.releaseEmbedding(id)
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        // Preemption is not an unsupported-language result. Retry background work after admission.
        if error is CancellationError {
          if case .embed(let input) = request, input.purpose == .query { throw error }
          continue
        }
        throw error
      }
    }
  }

  private func perform(_ request: EmbeddingRequest, timeout: TimeInterval) async throws
    -> EmbeddingResponse
  {
    try Task.checkCancellation()
    if worker == nil {
      await activity.prepareSearchModel(reservation)
      try Task.checkCancellation()
      worker = try InferenceWorkerConnection(executable: executable)
    }
    guard let worker else { throw MemoryEmbeddingError.unavailable }
    return try await withTaskCancellationHandler {
      do {
        if case .embed = request, identity != nil {
          // A pressure eviction may have discarded the prepared helper; preparation is idempotent.
          if !prepared { _ = try await prepare(worker) }
        }
        let response = try await send(request, worker: worker, timeout: timeout)
        if case .prepare = request {
          guard let value = response.identity, !value.isEmpty else {
            throw MemoryEmbeddingError.unavailable
          }
          guard identity == nil || identity == value else { throw MemoryEmbeddingError.unavailable }
          identity = value
          prepared = true
        }
        try Task.checkCancellation()
        await activity.rememberSearchModel(id: residencyID, reservation: reservation) {
          [weak self] in
          await self?.evict()
        }
        try Task.checkCancellation()
        guard !stopped, self.worker === worker else { throw CancellationError() }
        return response
      } catch {
        try Task.checkCancellation()
        throw error
      }
    } onCancel: {
      worker.stop()
    }
  }

  private func warmInBackground() {
    guard warming == nil else { return }
    warming = Task { [weak self] in await self?.finishWarmup() }
  }
  private func finishWarmup() async {
    defer { warming = nil }
    do {
      _ = try await exchange(.prepare(configuration), timeout: Self.preparationTimeout)
    } catch is CancellationError { return } catch {
      fputs("Memory search warmup failed: \(error)\n", stderr)
    }
  }

  private var prepared = false
  private func prepare(_ worker: InferenceWorkerConnection) async throws -> EmbeddingResponse {
    let response = try await send(
      .prepare(configuration), worker: worker, timeout: Self.preparationTimeout)
    guard response.identity == identity else { throw MemoryEmbeddingError.unavailable }
    prepared = true
    return response
  }

  private func send(
    _ request: EmbeddingRequest, worker: InferenceWorkerConnection,
    timeout: TimeInterval
  ) async throws -> EmbeddingResponse {
    let response = try await Task.detached {
      let deadline = InferenceDeadline(timeout: timeout)
      try worker.send(request, timeout: deadline.remaining())
      return try worker.receive(EmbeddingResponse.self, timeout: deadline.remaining())
    }.value
    try Task.checkCancellation()
    if let failure = response.failure {
      throw EmbeddingWorkerFailure(message: failure)
    }
    return response
  }

  package func evict() async {
    let previous = worker
    worker = nil
    prepared = false
    previous?.stop()
    await previous?.reap()
    await activity.forgetSearchModel(residencyID)
  }
  package func stop() async {
    stopped = true
    let pending = warming
    let active = operation
    pending?.cancel()
    active?.cancel()
    await evict()
    _ = await active?.result
    await pending?.value
  }
}

private struct EmbeddingWorkerFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
