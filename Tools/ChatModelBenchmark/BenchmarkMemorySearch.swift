import Foundation
import SilliesCore
import SilliesInference
import SilliesSearchModels
import SilliesVault

/// Optional production index over each synthetic fixture. Relevance labels never enter the worker.
struct BenchmarkMemorySearch: Sendable {
  struct Configuration: Decodable, Sendable {
    let provider: String
    let identity: String
    let helper: String
    let directory: String?
  }
  private enum Failure: Error { case invalidConfiguration, indexFailed }
  private static let indexDeadline: Duration = .seconds(45)
  private static let modelBytes: Int64 = 512 * 1024 * 1024
  private let worker: EmbeddingWorkerSession?
  private let access: MemoryEmbeddingAccess?

  static func prepare(_ configuration: Configuration?) async throws -> Self {
    guard let configuration else { return .init(worker: nil, access: nil) }
    guard configuration.helper.hasPrefix("/"),
      configuration.directory.map({ $0.hasPrefix("/") }) ?? true
    else { throw Failure.invalidConfiguration }
    let worker = EmbeddingWorkerSession(
      configuration: .init(
        provider: configuration.provider, identity: configuration.identity,
        directory: configuration.directory.map { URL(fileURLWithPath: $0) }),
      executable: URL(fileURLWithPath: configuration.helper),
      modelBytes: modelBytes, activity: .shared)
    do { return try await .init(worker: worker, access: worker.access()) } catch {
      await worker.stop()
      throw error
    }
  }

  func withIndex(in library: ConversationLibrary, work: () async throws -> Void) async throws {
    guard let access else { return try await work() }
    do {
      try await library.useMemoryEmbeddings(access)
      try await waitForIndex(in: library)
      try await work()
    } catch {
      try await library.useMemoryEmbeddings(nil)
      throw error
    }
    try await library.useMemoryEmbeddings(nil)
  }

  func stop() async { await worker?.stop() }

  private func waitForIndex(in library: ConversationLibrary) async throws {
    let deadline = ContinuousClock.now.advanced(by: Self.indexDeadline)
    while ContinuousClock.now < deadline {
      let (progress, failure) = try await library.memoryIndexStatus()
      if failure != nil { throw Failure.indexFailed }
      if let progress, progress.processed == progress.total { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw Failure.indexFailed
  }
}
