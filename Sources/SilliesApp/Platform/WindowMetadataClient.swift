import Foundation
import Synchronization
import WindowMetadataProtocol

/// Request serialization belongs to workers; UI stop uses only the separate short state lock.
final class WindowMetadataClient: Sendable {
  private struct State {
    var owners: Set<ObjectIdentifier> = []
    var generation = 0
    var connection: WindowMetadataConnection?
    mutating func takeConnection() -> WindowMetadataConnection? {
      defer { connection = nil }
      return connection
    }
  }
  private let request = Mutex(())
  private let state = Mutex(State())

  var processIdentifier: Int32? { state.withLock { $0.connection?.processIdentifier } }
  func start(owner: ObjectIdentifier) { _ = state.withLock { $0.owners.insert(owner) } }

  func stop(owner: ObjectIdentifier) {
    let stopped = state.withLock { state -> WindowMetadataConnection? in
      state.owners.remove(owner)
      guard state.owners.isEmpty else { return nil }
      state.generation += 1
      return state.takeConnection()
    }
    stopped?.stop()
  }

  func read(_ request: WindowMetadataRequest) -> WindowMetadataSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return self.request.withLock { _ in
      do {
        guard let active = try currentConnection() else { return nil }
        let snapshot = try active.read(request)
        let current = state.withLock { $0.connection === active && !$0.owners.isEmpty }
        return current ? snapshot : nil
      } catch {
        discardFailedConnection(error)
        return nil
      }
    }
  }

  private func discardFailedConnection(_ error: Error) {
    let stopped = state.withLock { $0.takeConnection() }
    stopped?.stop()
    if state.withLock({ !$0.owners.isEmpty }) {
      fputs("Window metadata read failed: \(error.localizedDescription)\n", stderr)
    }
  }

  private func currentConnection() throws -> WindowMetadataConnection? {
    let snapshot = state.withLock { $0 }
    guard !snapshot.owners.isEmpty else { return nil }
    if let existing = snapshot.connection { return existing }
    let created = try WindowMetadataConnection()
    let accepted = state.withLock { state in
      guard !state.owners.isEmpty, state.generation == snapshot.generation else { return false }
      state.connection = created
      return true
    }
    if !accepted { created.stop() }
    return accepted ? created : nil
  }
}
