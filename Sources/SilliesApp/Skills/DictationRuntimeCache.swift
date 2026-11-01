import Foundation
import SilliesCore
import SilliesSpeech

/// Retains one recently used dictation model for short bursts; idle and shutdown release its lease.
actor DictationRuntimeCache {
  private static let idleRetention: Duration = .seconds(120)
  private let registry: SpeechRuntimeRegistry
  private var runtime: SpeechRuntimeRegistry.Runtime?
  private var identity: SpeechModelDescriptor?
  private var expiry: Task<Void, Never>?
  private var generation = UUID()
  private var expiryID = UUID()
  init(registry: SpeechRuntimeRegistry) { self.registry = registry }

  func prepare(model: SpeechModelDescriptor) async throws {
    let token = generation
    defer { retainUntilIdle(ownedBy: token) }
    _ = try await preparedRuntime(for: model)
    guard generation == token else { throw CancellationError() }
  }

  func makeChannel(model: SpeechModelDescriptor, request: SpeechChannelRequest) async throws
    -> any LocalSpeechChannel
  {
    let token = generation
    defer { retainUntilIdle(ownedBy: token) }
    let runtime = try await preparedRuntime(for: model)
    let channel = try await runtime.makeChannel(request)
    guard generation == token, !Task.isCancelled else {
      channel.cancel()
      throw CancellationError()
    }
    return channel
  }

  private func preparedRuntime(for model: SpeechModelDescriptor) async throws
    -> SpeechRuntimeRegistry.Runtime
  {
    expiryID = UUID()
    expiry?.cancel()
    let token = generation
    if identity != model || runtime == nil {
      let prepared = try await registry.prepare(model)
      try Task.checkCancellation()
      guard generation == token else { throw CancellationError() }
      runtime = prepared
      identity = model
    }
    guard let runtime else {
      throw SpeechError.unavailable(String(localized: "Dictation model is not ready."))
    }
    try Task.checkCancellation()
    return runtime
  }

  private func retainUntilIdle(ownedBy generation: UUID) {
    guard self.generation == generation, runtime != nil else { return }
    expiry?.cancel()
    let token = UUID()
    expiryID = token
    expiry = Task { [weak self] in
      do { try await Task.sleep(for: Self.idleRetention) } catch { return }
      await self?.expire(token)
    }
  }

  private func expire(_ token: UUID) {
    guard expiryID == token else { return }
    stop()
  }
  func stop() {
    generation = UUID()
    expiryID = UUID()
    expiry?.cancel()
    expiry = nil
    runtime = nil
    identity = nil
  }
}
