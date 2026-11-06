import Foundation
import SilliesCore

/// Slow semantic work is optional. Cancel and drain it before returning the keyword results.
enum SemanticSearchDeadline {
  private static let budget: Duration = .milliseconds(150)
  static func perform<Value: Sendable>(_ work: @escaping @Sendable () async throws -> [Value])
    async throws
    -> [Value]
  {
    try await withThrowingTaskGroup(of: [Value].self) { tasks in
      tasks.addTask { try await work() }
      tasks.addTask {
        try await Task.sleep(for: budget)
        throw SearchEmbeddingError.unavailable
      }
      defer { tasks.cancelAll() }
      return try await tasks.next() ?? []
    }
  }
}
