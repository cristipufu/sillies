import Foundation
import Synchronization

/// One bounded inbox, one utility drain, one actor owning disk. Producers never wait for I/O.
package final class DiagnosticRecorder: Sendable {
  private struct Inbox {
    var enabled: Bool
    var closed = false
    var maintenance = 0
    var pending: [DiagnosticRecord] = []
    var dropped = 0
    var unreportedDrops = 0
    var sequence: UInt64 = 0
    var failure: DiagnosticFailure?
    var drain: Task<Void, Never>?
  }
  private let inbox: Mutex<Inbox>
  private let journal: DiagnosticJournal
  private let limits: DiagnosticLimits
  private let launch = UUID()
  private let now: @Sendable () -> Date

  package init(
    directory: URL, enabled: Bool, limits: DiagnosticLimits = .standard,
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    inbox = Mutex(Inbox(enabled: enabled))
    journal = DiagnosticJournal(directory: directory, limits: limits)
    self.limits = limits
    self.now = now
  }

  package var sink: DiagnosticSink {
    DiagnosticSink { [weak self] event in self?.record(event) }
  }
  package var failure: DiagnosticFailure? { inbox.withLock { $0.failure } }
  var pendingCount: Int { inbox.withLock { $0.pending.count } }
  var droppedCount: Int { inbox.withLock { $0.dropped } }

  private func record(_ event: DiagnosticEvent) {
    inbox.withLock { state in
      guard state.enabled, !state.closed else { return }
      guard state.failure == nil, state.maintenance == 0 else {
        incrementDropped(&state)
        return
      }
      if state.pending.count >= limits.pendingEvents {
        if !state.pending.isEmpty { state.pending.removeFirst() }
        incrementDropped(&state)
      }
      state.sequence &+= 1
      state.pending.append(
        DiagnosticRecord(event: event, launch: launch, sequence: state.sequence, now: now()))
      if state.drain == nil {
        state.drain = Task.detached(priority: .utility) { [weak self] in await self?.drain() }
      }
    }
  }

  private func drain() async {
    while true {
      let records = inbox.withLock { state -> [DiagnosticRecord] in
        guard !state.pending.isEmpty else {
          state.drain = nil
          return []
        }
        var records = state.pending
        state.pending.removeAll(keepingCapacity: true)
        if state.unreportedDrops > 0 {
          var event = DiagnosticEvent(.diagnostics, .eventsDropped)
          event.count = state.unreportedDrops
          state.sequence &+= 1
          records.append(
            DiagnosticRecord(event: event, launch: launch, sequence: state.sequence, now: now()))
          state.unreportedDrops = 0
        }
        return records
      }
      guard !records.isEmpty else { return }
      do { try await journal.append(records, now: now()) } catch {
        inbox.withLock { state in
          state.failure = DiagnosticFailure(error)
          state.pending.removeAll()
          state.drain = nil
        }
        await journal.reportStorageFailure()
        return
      }
    }
  }

  package func start() async throws {
    do { try await journal.prepare(now: now()) } catch {
      inbox.withLock { $0.failure = DiagnosticFailure(error) }
      await journal.reportStorageFailure()
      throw error
    }
  }

  package func setEnabled(_ enabled: Bool) async {
    let drain = inbox.withLock { state in
      state.enabled = enabled
      if enabled { state.failure = nil }
      return state.drain
    }
    if !enabled { await drain?.value }
  }

  package func clear() async throws {
    let drain = suspend()
    defer { resume() }
    await drain?.value
    try await journal.clear()
    inbox.withLock {
      $0.failure = nil
      $0.dropped = 0
      $0.unreportedDrops = 0
    }
  }

  package func export(to destination: URL, environment: DiagnosticEnvironment) async throws {
    let drain = suspend()
    defer { resume() }
    await drain?.value
    guard failure == nil else { throw DiagnosticStorageError.unavailable }
    try await journal.export(
      .init(
        destination: destination, environment: environment, droppedEvents: droppedCount, now: now())
    )
  }

  package func shutdown() async {
    let drain = inbox.withLock { state in
      state.closed = true
      return state.drain
    }
    await drain?.value
  }

  private func suspend() -> Task<Void, Never>? {
    inbox.withLock { state in
      state.maintenance += 1
      return state.drain
    }
  }

  private func resume() { inbox.withLock { $0.maintenance = max(0, $0.maintenance - 1) } }
  private func incrementDropped(_ state: inout Inbox) {
    if state.dropped < Int.max { state.dropped += 1 }
    if state.unreportedDrops < Int.max { state.unreportedDrops += 1 }
  }
}
