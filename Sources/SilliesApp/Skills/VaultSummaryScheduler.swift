import Foundation
import SilliesCore

/// Owns note-generation tasks; cancelled or replaced work cannot deliver stale results.
@MainActor
final class VaultSummaryScheduler {
  typealias Generator = @Sendable (SessionRecord) async -> LocalNotes
  private struct Pending {
    let generation: UUID
    let task: Task<Void, Never>
  }
  private let generate: Generator
  private var pending: [UUID: Pending] = [:]
  private var isEnabled = true
  var count: Int { pending.count }

  init(generate: @escaping Generator) { self.generate = generate }

  func schedule(_ record: SessionRecord, deliver: @escaping @MainActor (LocalNotes) -> Void) {
    guard isEnabled, record.summaryPending, pending[record.id] == nil else { return }
    let generation = UUID()
    let generate = generate
    let task = Task { [weak self] in
      let notes = await generate(record)
      guard !Task.isCancelled, let self, self.pending[record.id]?.generation == generation else {
        return
      }
      self.pending.removeValue(forKey: record.id)
      deliver(notes)
    }
    pending[record.id] = Pending(generation: generation, task: task)
  }

  func resume() { isEnabled = true }

  func cancel(id: UUID) { pending.removeValue(forKey: id)?.task.cancel() }

  func removeAll() {
    for work in pending.values { work.task.cancel() }
    pending.removeAll()
  }

  func stop() {
    isEnabled = false
    removeAll()
  }

  func flush() async {
    while !pending.isEmpty {
      let current = Array(pending.values)
      for work in current { await work.task.value }
    }
  }
}
