import Foundation
import Observation

/// Once accepted, a storage mutation outlives its view and drains before app termination.
@MainActor @Observable final class ChatPersistenceOperation<Output: Sendable> {
  private(set) var isRunning = false
  private struct Pending {
    let id = UUID()
    let task: Task<Output, Error>
    let accept: @MainActor @Sendable (Output) -> Void
  }
  @ObservationIgnored private var pending: Pending?

  func run(
    _ operation: @escaping @Sendable () async throws -> Output,
    accept: @escaping @MainActor @Sendable (Output) -> Void = { _ in }
  ) async throws -> Output {
    guard !isRunning else { throw Failure.busy }
    let current = Pending(
      task: Task.detached(priority: .utility, operation: operation), accept: accept)
    pending = current
    isRunning = true
    do {
      let value = try await current.task.value
      complete(current, result: .success(value))
      return value
    } catch {
      complete(current, result: .failure(error))
      throw error
    }
  }

  func finish(
    deliver: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
    completion: @escaping @MainActor @Sendable () -> Void
  ) {
    guard let pending else {
      completion()
      return
    }
    Task.detached {
      let result = await pending.task.result
      deliver {
        self.complete(pending, result: result)
        completion()
      }
    }
  }

  private func complete(_ current: Pending, result: Result<Output, Error>) {
    guard pending?.id == current.id else { return }
    pending = nil
    isRunning = false
    switch result {
    case .success(let output): current.accept(output)
    case .failure(let error): fputs("Conversation storage mutation failed: \(error)\n", stderr)
    }
  }

  private enum Failure: Error, LocalizedError {
    case busy
    var errorDescription: String? { String(localized: "Wait for the current change to finish.") }
  }
}
