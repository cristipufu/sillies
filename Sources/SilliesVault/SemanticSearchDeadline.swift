import Foundation
import SilliesCore

/// Slow semantic work is optional. Cancel and drain it before returning the keyword results.
enum SemanticSearchDeadline {
  enum Failure: Error { case exceeded }
  enum Purpose { case assistant, workspace }
  static func perform<Value: Sendable>(
    purpose: Purpose = .assistant, _ work: @escaping @Sendable () async throws -> [Value]
  )
    async throws
    -> [Value]
  {
    try await withThrowingTaskGroup(of: [Value].self) { tasks in
      tasks.addTask { try await work() }
      tasks.addTask {
        try await Task.sleep(for: purpose == .workspace ? .seconds(3) : .milliseconds(150))
        throw Failure.exceeded
      }
      defer { tasks.cancelAll() }
      return try await tasks.next() ?? []
    }
  }
}
