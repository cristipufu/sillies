import Foundation
import SilliesCore
import SilliesVault

enum VaultRetrievalQueries {
  struct Result: Codable {
    let id: String
    let keywords: [UUID]
    let semantic: [UUID]
    let fused: [UUID]
    let availability: String
    let keywordSeconds: Double
    let semanticSeconds: Double
    let exactSemantic: [UUID]?
    let exactSemanticSeconds: Double?
    let exactAvailability: String?
  }

  static func evaluate(
    _ fixture: VaultRetrievalFixture, run: VaultRetrievalRun, library: VaultLibrary,
    oracle: VaultRetrievalOracle?
  ) async throws {
    let output = run.directory.appendingPathComponent("results-\(run.provider).jsonl")
    let previous = try completedResults(output)
    let completed = Set(previous.map(\.id))
    guard completed.count == previous.count,
      completed.isSubset(of: Set(fixture.queries.map(\.id)))
    else { throw ProbeError.usage }
    if run.provider != "keywords" {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while await library.isPreparingSearch, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
      }
      let (progress, failure) = try await library.searchIndexStatus()
      guard failure == nil, let progress, progress.processed == progress.total,
        await !library.isPreparingSearch
      else { throw ProbeError.indexFailed }
    }
    let deadline = ContinuousClock.now.advanced(by: VaultRetrievalRun.sliceDuration)
    var results = previous
    for query in fixture.queries where !completed.contains(query.id) {
      results.append(try await evaluate(query, library: library, oracle: oracle))
      let encoded = try results.reduce(into: Data()) { data, result in
        data.append(try JSONEncoder().encode(result))
        data.append(10)
      }
      try encoded.write(to: output, options: .atomic)
      if ContinuousClock.now >= deadline { break }
    }
    try VaultRetrievalBenchmark.emit(
      VaultRetrievalBenchmark.Progress(
        stage: "query", processed: results.count, total: fixture.queries.count,
        complete: results.count == fixture.queries.count))
  }

  private static func evaluate(
    _ query: VaultRetrievalFixture.Query, library: VaultLibrary, oracle: VaultRetrievalOracle?
  )
    async throws -> Result
  {
    let keywordStart = ContinuousClock.now
    let keywords = try await library.workspacePage(query.workspace).records.prefix(20).map(\.id)
    let keywordSeconds = seconds(keywordStart.duration(to: .now))
    let semanticStart = ContinuousClock.now
    let request = VaultSearchRequest(workspace: query.workspace, limit: 20)
    let related = try await library.relatedSearch(request)
    let semanticSeconds = seconds(semanticStart.duration(to: .now))
    let semantic = related.matches.map(\.header.id)
    let fused = VaultRankFusion.merge([keywords, semantic], identifiedBy: \.self, limit: 5)
    let exactStart = ContinuousClock.now
    let exact = try await oracle?.search(request)
    return Result(
      id: query.id, keywords: Array(keywords.prefix(5)), semantic: Array(semantic.prefix(5)),
      fused: fused,
      availability: String(describing: related.availability), keywordSeconds: keywordSeconds,
      semanticSeconds: semanticSeconds,
      exactSemantic: exact.map { $0.matches.prefix(5).map(\.header.id) },
      exactSemanticSeconds: oracle == nil ? nil : seconds(exactStart.duration(to: .now)),
      exactAvailability: exact.map { String(describing: $0.availability) })
  }

  private static func completedResults(_ url: URL) throws -> [Result] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    guard bytes < 16 * 1_024 * 1_024 else { throw ProbeError.usage }
    return try Data(contentsOf: url).split(separator: 10).map {
      try JSONDecoder().decode(Result.self, from: Data($0))
    }
  }
  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
