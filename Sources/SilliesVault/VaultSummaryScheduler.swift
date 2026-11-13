import Foundation
import SilliesCore
import SilliesReasoning

/// Admits one notes job at a time. Failed delivery retains its result until an explicit retry.
@MainActor package final class VaultSummaryScheduler {
  package typealias Generator = @Sendable (VaultNotesInput) async -> LocalNotes
  private struct Request {
    let deliver: @MainActor (LocalNotes, VaultNotesInput.Revision) async throws -> Bool
  }
  private struct Completion {
    let notes: LocalNotes
    let revision: VaultNotesInput.Revision
    let request: Request
  }
  private enum Work {
    case generate(Request)
    case deliver(Completion)
  }
  private struct Active {
    let id: UUID
    let work: Work
    let task: Task<Void, Never>
  }
  private struct Failed {
    let id: UUID
    let work: Work
  }
  private let generate: Generator
  private let load: @Sendable (UUID) async throws -> VaultNotesInput?
  private var pending: [UUID: Work] = [:]
  private var order: [UUID] = []
  private var active: Active?
  private var failed: Failed?
  private var isEnabled = true
  package var reportFailure: @MainActor (String?) -> Void = { _ in }
  package var count: Int {
    var count = pending.count
    if let active, pending[active.id] == nil { count += 1 }
    if let failed, pending[failed.id] == nil, active?.id != failed.id { count += 1 }
    return count
  }

  package init(
    load: @escaping @Sendable (UUID) async throws -> VaultNotesInput?, generate: @escaping Generator
  ) {
    self.load = load
    self.generate = generate
  }

  package func schedule(
    _ id: UUID,
    deliver: @escaping @MainActor (LocalNotes, VaultNotesInput.Revision) async throws -> Bool
  ) {
    guard isEnabled, pending[id] == nil, failed?.id != id else { return }
    if active?.id == id, active?.task.isCancelled == false { return }
    enqueue(id, work: .generate(.init(deliver: deliver)))
    pump()
  }

  package func resume() {
    isEnabled = true
    pump()
  }

  package func retry() {
    guard let failed else { return }
    self.failed = nil
    reportFailure(nil)
    pending[failed.id] = failed.work
    order.insert(failed.id, at: 0)
    pump()
  }

  package func cancel(id: UUID) {
    pending.removeValue(forKey: id)
    order.removeAll { $0 == id }
    if active?.id == id { active?.task.cancel() }
    if failed?.id == id { clearFailure() }
    pump()
  }

  package func removeAll() {
    clearQueue()
    clearFailure()
  }

  package func stop() {
    isEnabled = false
    pending = pending.filter { _, work in
      if case .deliver = work { return true }
      return false
    }
    order.removeAll { pending[$0] == nil }
    if let active, !active.task.isCancelled, case .deliver = active.work {
      enqueue(active.id, work: active.work)
    }
    active?.task.cancel()
  }

  package func flush() async {
    while let task = active?.task { await task.value }
  }

  private func clearQueue() {
    pending.removeAll()
    order.removeAll()
    active?.task.cancel()
  }
  private func clearFailure() {
    failed = nil
    reportFailure(nil)
  }
  private func enqueue(_ id: UUID, work: Work) {
    guard pending[id] == nil else { return }
    pending[id] = work
    order.append(id)
  }

  private func pump() {
    guard isEnabled, active == nil, failed == nil, !order.isEmpty else { return }
    let id = order.removeFirst()
    guard let work = pending.removeValue(forKey: id) else { return }
    let task = Task { [weak self] in
      guard let self else { return }
      await run(work, id: id)
      active = nil
      pump()
    }
    active = Active(id: id, work: work, task: task)
  }

  private func run(_ work: Work, id: UUID) async {
    var recovery = work
    do {
      guard let completion = try await prepare(work, id: id), !Task.isCancelled, isEnabled else {
        return
      }
      recovery = .deliver(completion)
      let accepted = try await completion.request.deliver(completion.notes, completion.revision)
      if !accepted { try await requeueChangedInput(id, after: completion) }
    } catch {
      guard !(error is CancellationError), !Task.isCancelled else { return }
      fputs("Could not complete pending Vault notes: \(error)\n", stderr)
      failed = .init(id: id, work: recovery)
      reportFailure(error.localizedDescription)
    }
  }

  private func prepare(_ work: Work, id: UUID) async throws -> Completion? {
    switch work {
    case .deliver(let completion): return completion
    case .generate(let request):
      guard let input = try await load(id), input.record.summaryPending, !Task.isCancelled else {
        return nil
      }
      let notes = await generate(input)
      return .init(notes: notes, revision: input.revision, request: request)
    }
  }

  private func requeueChangedInput(_ id: UUID, after completion: Completion) async throws {
    guard !Task.isCancelled, isEnabled,
      let latest = try await load(id), latest.record.summaryPending,
      latest.revision != completion.revision, !Task.isCancelled, isEnabled
    else { return }
    enqueue(id, work: .generate(completion.request))
  }
}
