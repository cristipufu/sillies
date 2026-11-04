import Foundation
import SilliesCore

/// Slow semantic work is optional. Cancel and drain it before returning the keyword results.
enum MemorySearchDeadline {
  private static let budget: Duration = .milliseconds(150)
  static func perform(_ work: @escaping @Sendable () async throws -> [CompanionMemory]) async throws
    -> [CompanionMemory]
  {
    try await withThrowingTaskGroup(of: [CompanionMemory].self) { tasks in
      tasks.addTask { try await work() }
      tasks.addTask {
        try await Task.sleep(for: budget)
        throw MemoryEmbeddingError.unavailable
      }
      defer { tasks.cancelAll() }
      return try await tasks.next() ?? []
    }
  }
}
