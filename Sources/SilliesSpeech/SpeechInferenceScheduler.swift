import Foundation
import SilliesInference

/// Serializes access to shared model weights across independent audio sources.
/// An actor alone would permit overlapping predictions at suspension points.
package actor SpeechInferenceScheduler: SpeechWindowEngine {
  package nonisolated let finalizationPolicy: SpeechFinalizationPolicy
  private struct Job {
    let id: UUID
    let request: SpeechWindowRequest
    let continuation: CheckedContinuation<SpeechWindowResult, Error>
  }
  private static let maximumPendingJobs = 4
  private let engine: any SpeechWindowEngine
  private let activity: InferenceActivity
  private var pending: [Job] = []
  private var active: (id: UUID, task: Task<Void, Never>)?

  package init(engine: any SpeechWindowEngine, activity: InferenceActivity = .shared) {
    self.engine = engine
    self.activity = activity
    finalizationPolicy = engine.finalizationPolicy
  }

  package func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard pending.count < Self.maximumPendingJobs else {
          continuation.resume(throwing: SpeechError.overloaded)
          return
        }
        let job = Job(id: id, request: request, continuation: continuation)
        let index =
          pending.firstIndex {
            $0.request.context.priority.rawValue < request.context.priority.rawValue
          }
          ?? pending.endIndex
        pending.insert(job, at: index)
        startNext()
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  private func startNext() {
    guard active == nil, !pending.isEmpty else { return }
    let job = pending.removeFirst()
    let priority = job.request.context.priority.taskPriority
    let task = Task(priority: priority) {
      await activity.beginSpeech()
      let result: Result<SpeechWindowResult, any Error>
      do {
        try Task.checkCancellation()
        let transcript = try await engine.transcribe(job.request)
        try Task.checkCancellation()
        result = .success(transcript)
      } catch { result = .failure(error) }
      await activity.endSpeech()
      job.continuation.resume(with: result)
      completed(job.id)
    }
    active = (job.id, task)
  }

  private func completed(_ id: UUID) {
    guard active?.id == id else { return }
    active = nil
    startNext()
  }

  private func cancel(_ id: UUID) {
    if active?.id == id { active?.task.cancel() }
    if let index = pending.firstIndex(where: { $0.id == id }) {
      pending.remove(at: index).continuation.resume(throwing: CancellationError())
    }
  }
}
