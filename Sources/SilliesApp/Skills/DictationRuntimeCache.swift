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
  init(registry: SpeechRuntimeRegistry) { self.registry = registry }

  func makeChannel(model: SpeechModelDescriptor, request: SpeechChannelRequest) async throws
    -> any LocalSpeechChannel
  {
    expiry?.cancel()
    let token = generation
    if identity != model || runtime == nil {
      let prepared = try await registry.prepare(model)
      try Task.checkCancellation()
      guard generation == token else { throw CancellationError() }
      runtime = prepared
      identity = model
    }
    guard let runtime else { throw SpeechError.unavailable("Dictation model is not ready.") }
    let channel = try await runtime.makeChannel(request)
    guard generation == token, !Task.isCancelled else {
      channel.cancel()
      throw CancellationError()
    }
    expiry = Task { [weak self] in
      do { try await Task.sleep(for: Self.idleRetention) } catch { return }
      await self?.stop()
    }
    return channel
  }
  func stop() {
    generation = UUID()
    expiry?.cancel()
    expiry = nil
    runtime = nil
    identity = nil
  }
}
