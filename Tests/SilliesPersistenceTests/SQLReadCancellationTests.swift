import Foundation
import Testing

@testable import SilliesPersistence

@Test func cancellationInterruptsAnExecutingSQLReadAndRemovesItsHandler() async throws {
  let started = AsyncStream<Void>.makeStream()
  let read = Task.detached {
    defer { started.continuation.finish() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
    let sql = try VaultSQLConnection(url: directory.appendingPathComponent("cancellation.sqlite"))
    var signalled = false
    do {
      try sql.cancellableRead {
        try sql.rows(
          """
          WITH RECURSIVE numbers(n) AS (
            SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<100000000
          ) SELECT n FROM numbers
          """
        ) { _ in
          if !signalled {
            signalled = true
            started.continuation.yield(())
          }
        }
      }
      Issue.record("The cancelled recursive query completed instead of being interrupted")
    } catch is CancellationError {
      // This task is still cancelled. An unscoped progress handler would interrupt this query.
      let result = try sql.integer(
        """
        WITH RECURSIVE numbers(n) AS (
          SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<2000
        ) SELECT MAX(n) FROM numbers
        """)
      #expect(result == 2_000)
      #expect(throws: CancellationError.self) { try sql.cancellableRead { 1 } }
    }
  }
  for await _ in started.stream { break }
  let cancelled = ContinuousClock.now
  read.cancel()
  try await read.value
  #expect(cancelled.duration(to: .now) < .seconds(1))
}
