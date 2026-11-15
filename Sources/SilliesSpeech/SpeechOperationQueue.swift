import Foundation

private enum SpeechOperationQueuePolicy { static let maximumPendingJobs = 4 }

/// One bounded native operation at a time, including across actor suspension points.
package actor SpeechOperationQueue<Input: Sendable, Output: Sendable> {
  private struct Job {
    let id: UUID
    let input: Input
    let priority: TaskPriority
    let continuation: CheckedContinuation<Output, any Error>
  }
  private let operation: @Sendable (Input) async throws -> Output
  private var pending: [Job] = []
  private var active: (id: UUID, task: Task<Void, Never>)?

  package init(operation: @escaping @Sendable (Input) async throws -> Output) {
    self.operation = operation
  }

  package func submit(_ input: Input, priority: TaskPriority) async throws -> Output {
    let id = UUID()
    let output: Output = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard pending.count < SpeechOperationQueuePolicy.maximumPendingJobs else {
          continuation.resume(throwing: SpeechError.overloaded)
          return
        }
        let job = Job(id: id, input: input, priority: priority, continuation: continuation)
        let index =
          pending.firstIndex { $0.priority.rawValue < priority.rawValue } ?? pending.endIndex
        pending.insert(job, at: index)
        startNext()
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
    try Task.checkCancellation()
    return output
  }

  private func startNext() {
    guard active == nil, !pending.isEmpty else { return }
    let job = pending.removeFirst()
    let task = Task(priority: job.priority) {
      let result: Result<Output, any Error>
      do {
        try Task.checkCancellation()
        let output = try await operation(job.input)
        try Task.checkCancellation()
        result = .success(output)
      } catch { result = .failure(error) }
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
