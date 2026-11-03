import Foundation
import SilliesCore
import SilliesTextModels

/// One coalescing producer for all companions. Interactive admission cancels its current slice.
actor ConversationCheckpointMaintenance {
  struct Schedule: Sendable {
    let idleDelay: Duration
    let sliceDeadline: Duration
    static let standard = Self(idleDelay: .seconds(2), sliceDeadline: .seconds(30))
  }
  private struct Active {
    let job: ConversationCheckpointJob
    let task: Task<Bool, Error>
  }
  private static let maximumPendingConversations = 16
  private let owner = UUID()
  private let repository: any ConversationRepository
  private let resolveBackend: @Sendable () async -> any ReasoningBackend
  private let turns: ReasoningTurnGate
  private let schedule: Schedule
  private var lifetimes: Set<UUID> = []
  private var pending: [String: ConversationCheckpointJob] = [:]
  private var order: [String] = []
  private var active: Active?
  private var producer: Task<Void, Never>?
  var pendingConversationCount: Int { pending.count }

  init(
    repository: any ConversationRepository,
    resolveBackend: @escaping @Sendable () async -> any ReasoningBackend,
    turns: ReasoningTurnGate, schedule: Schedule = .standard
  ) {
    self.repository = repository
    self.resolveBackend = resolveBackend
    self.turns = turns
    self.schedule = schedule
  }

  func retain(for lifetime: TextModelLifetime) async {
    guard lifetimes.contains(lifetime.id) || lifetimes.count < Self.maximumPendingConversations
    else { return }
    lifetimes.insert(lifetime.id)
    await lifetime.onEnd(owner: owner) { [weak self] in await self?.stop(lifetime.id) }
  }

  func enqueue(_ context: ChatContext) {
    guard let job = ConversationCheckpointJob(context) else { return }
    enqueue(job)
    startIfNeeded()
  }

  private func startIfNeeded() {
    if producer == nil, !pending.isEmpty {
      producer = Task(priority: .utility) { [weak self] in await self?.drain() }
    }
  }

  func stop(_ session: UUID) async {
    lifetimes.remove(session)
    for (key, job) in pending where job.sessionID == session { pending[key] = nil }
    order.removeAll { pending[$0] == nil }
    if let work = active, work.job.sessionID == session {
      work.task.cancel()
      _ = await work.task.result
    }
    if pending.isEmpty, active == nil { producer?.cancel() }
  }

  private func enqueue(_ job: ConversationCheckpointJob) {
    guard lifetimes.contains(job.sessionID) else { return }
    let key = job.handle.companionID
    if pending[key] == nil {
      guard pending.count < Self.maximumPendingConversations else { return }
      order.append(key)
    }
    pending[key] = job
  }

  private func drain() async {
    defer {
      producer = nil
      startIfNeeded()
    }
    while !pending.isEmpty {
      do { try await Task.sleep(for: schedule.idleDelay) } catch { return }
      guard !Task.isCancelled, let job = dequeue() else { return }
      let work = Task { [repository, resolveBackend, turns, schedule] in
        try await turns.performCheckpoint {
          try await Self.withDeadline(schedule.sliceDeadline) {
            let selected = await resolveBackend()
            guard let backend = selected as? any ConversationBackend,
              await backend.availabilityNotice(localeIdentifier: job.languageIdentifier) == nil
            else { return false }
            return try await ConversationCheckpointWorker(repository: repository, backend: backend)
              .advance(job)
          }
        }
      }
      active = .init(job: job, task: work)
      do {
        if try await work.value { reschedule(job) }
      } catch is CancellationError {
        // Interactive work preempts a slice; a closed lifetime cannot re-enter the queue.
        reschedule(job)
      } catch {
        fputs("Conversation checkpoint deferred: \(error)\n", stderr)
      }
      active = nil
    }
  }

  private func reschedule(_ job: ConversationCheckpointJob) {
    if pending[job.handle.companionID] == nil { enqueue(job) }
  }

  private func dequeue() -> ConversationCheckpointJob? {
    guard !order.isEmpty else { return nil }
    return pending.removeValue(forKey: order.removeFirst())
  }

  private static func withDeadline<Value: Sendable>(
    _ duration: Duration, operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: duration)
        throw CheckpointDeadline.exceeded
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else { throw CancellationError() }
      return result
    }
  }
}

private enum CheckpointDeadline: Error { case exceeded }
