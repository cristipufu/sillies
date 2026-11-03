import Foundation

actor TextWorkerModel: PreparedTextModel {
  private let configuration: TextModelPreparation
  private let executable: URL
  private var connection: TextWorkerConnection?
  private var busy = false
  private var idleCleanup: Task<Void, Never>?
  private var activeSessionID: UUID?
  private var retainedSessionID: UUID?
  private var pendingSessionReleases: Set<UUID> = []

  init(configuration: TextModelPreparation, executable: URL) {
    self.configuration = configuration
    self.executable = executable
  }

  func generate(_ request: TextGenerationRequest) async throws -> String {
    let output = try await complete(request)
    guard output.calls.isEmpty else { throw TextModelError.invalidResponse }
    return output.text
  }
  func complete(_ request: TextGenerationRequest) async throws -> TextGenerationOutput {
    try await stream(request, receive: { _ in })
  }
  func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    // Session teardown shares the pipe with generation. A newly opened conversation waits for
    // its bounded control exchange instead of failing because the previous one just closed.
    if let idleCleanup { await idleCleanup.value }
    guard !busy else { throw TextModelError.busy }
    busy = true
    defer {
      busy = false
      activeSessionID = nil
    }
    try Task.checkCancellation()
    let worker = try connection ?? TextWorkerConnection(executable: executable)
    connection = worker
    if request.operation == .generate { activeSessionID = request.sessionID }
    let message = TextInferenceRequest(configuration: configuration, generation: request)
    return try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        let output = try await worker.stream(message, receive: receive)
        try Task.checkCancellation()
        if request.operation == .generate { retainedSessionID = request.sessionID }
        await releasePendingSessions(using: worker)
        try Task.checkCancellation()
        return output
      } catch TextModelError.contextLimit {
        await releasePendingSessions(using: worker)
        throw TextModelError.contextLimit
      } catch {
        worker.stop()
        await worker.reap()
        connection = nil
        retainedSessionID = nil
        pendingSessionReleases.removeAll()
        throw error
      }
    } onCancel: {
      worker.stop()
    }
  }

  func stop() async {
    retainedSessionID = nil
    pendingSessionReleases.removeAll()
    let worker = connection
    connection = nil
    worker?.stop()
    await worker?.reap()
    if let idleCleanup { await idleCleanup.value }
  }

  func releaseConversation(_ sessionID: UUID) async {
    // Only the in-flight and previously retained session can own native state. This bounds the
    // deferred set and avoids interleaving control frames with an acknowledged text stream.
    guard sessionID == activeSessionID || sessionID == retainedSessionID else { return }
    pendingSessionReleases.insert(sessionID)
    guard !busy, idleCleanup == nil, let worker = connection else { return }
    let cleanup = Task { await finishIdleCleanup(using: worker) }
    idleCleanup = cleanup
    await cleanup.value
  }

  private func finishIdleCleanup(using worker: TextWorkerConnection) async {
    defer { idleCleanup = nil }
    await releasePendingSessions(using: worker)
  }

  private func releasePendingSessions(using worker: TextWorkerConnection) async {
    while let id = pendingSessionReleases.first {
      pendingSessionReleases.remove(id)
      if retainedSessionID == id { retainedSessionID = nil }
      do {
        _ = try await worker.stream(
          .init(configuration: configuration, generation: .releasingSession(id)), receive: { _ in })
      } catch {
        fputs("Failed to release native text conversation: \(error)\n", stderr)
        worker.stop()
        await worker.reap()
        connection = nil
        retainedSessionID = nil
        pendingSessionReleases.removeAll()
        return
      }
    }
  }
}
