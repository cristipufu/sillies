import Foundation
import WindowMetadataProtocol

/// Only worker callers acquire requestLock. UI stop/pause uses a separate, short state lock.
final class WindowMetadataClient: @unchecked Sendable {
  private struct State {
    let hasOwners: Bool
    let generation: Int
    let connection: WindowMetadataConnection?
  }

  private let requestLock = NSLock()
  private let stateLock = NSLock()
  private var owners: Set<ObjectIdentifier> = []
  private var generation = 0
  private var connection: WindowMetadataConnection?

  var processIdentifier: Int32? {
    stateLock.withLock { connection?.processIdentifier }
  }

  func start(owner: ObjectIdentifier) {
    _ = stateLock.withLock { owners.insert(owner) }
  }

  func stop(owner: ObjectIdentifier) {
    let stopped = stateLock.withLock { () -> WindowMetadataConnection? in
      owners.remove(owner)
      guard owners.isEmpty else { return nil }
      generation += 1
      return takeConnection()
    }
    stopped?.stop()
  }

  func read(_ request: WindowMetadataRequest) -> WindowMetadataSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return requestLock.withLock {
      do {
        guard let active = try currentConnection() else { return nil }
        let snapshot = try active.read(request)
        // Pause/restart can happen while the worker is reading the previous connection.
        let isCurrent = stateLock.withLock { connection === active && !owners.isEmpty }
        return isCurrent ? snapshot : nil
      } catch {
        discardFailedConnection(error)
        return nil
      }
    }
  }

  private func takeConnection() -> WindowMetadataConnection? {
    defer { connection = nil }
    return connection
  }

  private func discardFailedConnection(_ error: Error) {
    let stopped = stateLock.withLock { takeConnection() }
    stopped?.stop()
    if stateLock.withLock({ !owners.isEmpty }) {
      fputs("Window metadata read failed: \(error.localizedDescription)\n", stderr)
    }
  }

  private func currentConnection() throws -> WindowMetadataConnection? {
    let state = stateLock.withLock {
      State(hasOwners: !owners.isEmpty, generation: generation, connection: connection)
    }
    guard state.hasOwners else { return nil }
    if let existing = state.connection { return existing }
    let created = try WindowMetadataConnection()
    let accepted = stateLock.withLock {
      guard !owners.isEmpty, generation == state.generation else { return false }
      connection = created
      return true
    }
    if !accepted { created.stop() }
    return accepted ? created : nil
  }
}
