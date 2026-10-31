import Foundation
import SilliesCore
import SilliesPersistence
import SilliesReasoning

/// Admits one notes job at a time. Canceled work retains its slot until its producer returns.
@MainActor package final class VaultSummaryScheduler {
  package typealias Generator = @Sendable (SessionRecord) async -> LocalNotes
  private struct Request {
    let deliver: @MainActor (LocalNotes, UUID) async -> Void
  }
  private struct Active {
    let id: UUID
    let task: Task<Void, Never>
  }
  private let generate: Generator
  private let load: @Sendable (UUID) async throws -> SessionRecord?
  private var pending: [UUID: Request] = [:]
  private var order: [UUID] = []
  private var active: Active?
  private var isEnabled = true
  package var count: Int { pending.count + (active == nil ? 0 : 1) }

  package init(
    load: @escaping @Sendable (UUID) async throws -> SessionRecord?, generate: @escaping Generator
  ) {
    self.load = load
    self.generate = generate
  }

  package func schedule(_ id: UUID, deliver: @escaping @MainActor (LocalNotes, UUID) async -> Void)
  {
    guard isEnabled, pending[id] == nil else { return }
    if active?.id == id, active?.task.isCancelled == false { return }
    pending[id] = Request(deliver: deliver)
    order.append(id)
    pump()
  }

  package func resume() {
    isEnabled = true
    pump()
  }

  package func cancel(id: UUID) {
    pending.removeValue(forKey: id)
    order.removeAll { $0 == id }
    if active?.id == id { active?.task.cancel() }
  }

  package func removeAll() {
    pending.removeAll()
    order.removeAll()
    active?.task.cancel()
  }

  package func stop() {
    isEnabled = false
    removeAll()
  }

  package func flush() async {
    while let task = active?.task { await task.value }
  }

  private func pump() {
    guard isEnabled, active == nil, !order.isEmpty else { return }
    let id = order.removeFirst()
    guard let request = pending.removeValue(forKey: id) else { return }
    let task = Task { [weak self, generate, load] in
      do {
        if let record = try await load(id), record.summaryPending, !Task.isCancelled {
          let notes = await generate(record)
          if !Task.isCancelled, self?.isEnabled == true {
            await request.deliver(notes, record.processingRevision.notes)
          }
        }
      } catch { fputs("Could not load pending Vault notes: \(error)\n", stderr) }
      self?.active = nil
      self?.pump()
    }
    active = Active(id: id, task: task)
  }
}
