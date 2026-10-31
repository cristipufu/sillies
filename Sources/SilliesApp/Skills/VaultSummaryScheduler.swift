import Foundation
import SilliesCore

/// Admits one notes job at a time. Canceled work retains its slot until its producer returns.
@MainActor final class VaultSummaryScheduler {
  typealias Generator = @Sendable (SessionRecord) async -> LocalNotes
  private struct Request {
    let record: SessionRecord
    let deliver: @MainActor (LocalNotes) -> Void
  }
  private struct Active {
    let id: UUID
    let task: Task<Void, Never>
  }
  private let generate: Generator
  private var pending: [UUID: Request] = [:]
  private var order: [UUID] = []
  private var active: Active?
  private var isEnabled = true
  var count: Int { pending.count + (active == nil ? 0 : 1) }

  init(generate: @escaping Generator) { self.generate = generate }

  func schedule(_ record: SessionRecord, deliver: @escaping @MainActor (LocalNotes) -> Void) {
    guard isEnabled, record.summaryPending, pending[record.id] == nil else { return }
    if active?.id == record.id, active?.task.isCancelled == false { return }
    pending[record.id] = Request(record: record, deliver: deliver)
    order.append(record.id)
    pump()
  }

  func resume() {
    isEnabled = true
    pump()
  }

  func cancel(id: UUID) {
    pending.removeValue(forKey: id)
    order.removeAll { $0 == id }
    if active?.id == id { active?.task.cancel() }
  }

  func removeAll() {
    pending.removeAll()
    order.removeAll()
    active?.task.cancel()
  }

  func stop() {
    isEnabled = false
    removeAll()
  }

  func flush() async {
    while let task = active?.task { await task.value }
  }

  private func pump() {
    guard isEnabled, active == nil, !order.isEmpty else { return }
    let id = order.removeFirst()
    guard let request = pending.removeValue(forKey: id) else { return }
    let task = Task { [weak self, generate] in
      let notes = await generate(request.record)
      guard let self else { return }
      if !Task.isCancelled, self.isEnabled { request.deliver(notes) }
      self.active = nil
      self.pump()
    }
    active = Active(id: id, task: task)
  }
}
