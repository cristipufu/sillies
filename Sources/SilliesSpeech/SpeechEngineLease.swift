import Foundation

/// Joins in-flight inference before reset, including engines that finish a native call after cancellation.
package actor SpeechEngineLease: SpeechWindowEngine {
  private let engine: any ReusableSpeechEngine
  private let recycle: @Sendable (any ReusableSpeechEngine) async -> Void
  private var active: Task<SpeechWindowResult, Error>?
  private var releaseTask: Task<Void, Never>?
  private var reusable = true

  init(
    engine: any ReusableSpeechEngine,
    recycle: @escaping @Sendable (any ReusableSpeechEngine) async -> Void
  ) {
    self.engine = engine
    self.recycle = recycle
  }

  package func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    try Task.checkCancellation()
    guard releaseTask == nil else { throw CancellationError() }
    guard active == nil else { throw SpeechError.overloaded }
    let task = Task { try await engine.transcribe(request) }
    active = task
    defer { active = nil }
    do {
      return try await withTaskCancellationHandler {
        let result = try await task.value
        try Task.checkCancellation()
        return result
      } onCancel: {
        task.cancel()
      }
    } catch {
      if !(error is CancellationError) { reusable = false }
      throw error
    }
  }

  package func release() async {
    if let releaseTask { return await releaseTask.value }
    let task = Task { [active, engine, recycle] in
      active?.cancel()
      if let active {
        let result = await active.result
        if case .failure(let error) = result, !(error is CancellationError) { return }
      }
      guard reusable else { return }
      do {
        try await engine.resetForReuse()
        await recycle(engine)
      } catch {
        fputs(
          "Speech engine reset failed; discarding runtime: \(error.localizedDescription)\n", stderr)
      }
    }
    releaseTask = task
    await task.value
  }
}
