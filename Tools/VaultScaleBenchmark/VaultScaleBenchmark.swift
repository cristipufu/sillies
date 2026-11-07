import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Resumable synthetic qualification. Seed slices have a wall-clock limit; query runs never build data.
@main enum VaultScaleBenchmark {
  private static let batchCount = 500
  private static let sampleCount = 15
  static func main() async {
    do { try await run() } catch {
      fputs("Vault scale benchmark failed: \(error)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  private static func run() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 5, let count = Int(arguments[3]), (1...1_000_000).contains(count),
      let seconds = Double(arguments[4]), seconds > 0, seconds <= 30
    else { throw ProbeError.usage }
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let library = VaultLibrary(directory: directory, cacheBytes: 0)
    _ = try await library.snapshot()
    switch arguments[1] {
    case "seed": try await seed(library, target: count, seconds: seconds)
    case "seed-meetings":
      try await VaultMeetingFixture.seed(library, target: count, seconds: seconds)
    case "query": try await query(library)
    case "concurrency": try await concurrency(library)
    case "long-document": try await longDocument(library)
    case "retention": try await maintenance(library, mutation: .init(retention: .recent200))
    case "clear": try await maintenance(library, mutation: .init(deletion: .all))
    case "drain": try await VaultLifecycleProbe.drain(library, seconds: seconds)
    case "backup": try await VaultLifecycleProbe.backup(library, directory: directory)
    case "restore": try await VaultLifecycleProbe.restore(directory: directory)
    case "verify-restore": try await VaultLifecycleProbe.verifyRestore(directory: directory)
    default: throw ProbeError.usage
    }
  }

  private static func seed(_ library: VaultLibrary, target: Int, seconds: Double) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    var count = try await library.snapshot().page.total
    while count < target, ContinuousClock.now < deadline {
      let end = min(target, count + batchCount)
      let records = try (count..<end).map(makeRecord)
      _ = try await library.commit(.init(records: records.map { .insert($0) }))
      count = end
    }
    try emit(SeedResult(records: count, target: target, complete: count == target))
  }

  private static func makeRecord(_ index: Int) throws -> SessionRecord {
    let suffix = String(format: "%012llX", Int64(index + 1))
    guard let id = UUID(uuidString: "00000000-0000-4000-8000-" + suffix) else {
      throw ProbeError.usage
    }
    return SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "pogo", characterName: "Pogo",
        source: .init(appName: "Synthetic meeting", windowTitle: "Project \(index % 137)")),
      content: .init(
        text: .init(
          transcript:
            "We discussed the project roadmap, the next review and the meeting notes. Receipt\(index) belongs to project \(index % 137). The team agreed to check the accessibility improvements and offline behavior before Friday.\nThe follow-up includes design review, quality checks and a careful release plan."
        ),
        notes: .init(
          summary: "Project review with decisions and next steps.",
          actionItems: ["Review the design", "Check offline behavior"])),
      metadata: .init(
        id: id, createdAt: Date(timeIntervalSince1970: Double(index)), durationSeconds: 900))
  }

  private static func query(_ library: VaultLibrary) async throws {
    let total = try await library.snapshot().page.total
    let inputs: [(String, VaultWorkspaceQuery)] = [
      ("recent", .init()),
      ("broad_newest", .init(text: "meeting", ordering: .newest)),
      ("recently_edited", .init(ordering: .modified)),
      ("broad_relevance", .init(text: "meeting", ordering: .relevance)),
      ("rare", .init(text: "receipt\(max(0,total-50))", ordering: .relevance)),
    ]
    for (name, input) in inputs {
      var samples: [Double] = []
      var returned = 0
      for _ in 0..<sampleCount {
        let started = ContinuousClock.now
        let page = try await library.workspacePage(input)
        returned = page.records.count
        samples.append(milliseconds(started.duration(to: .now)))
      }
      let ordered = samples.sorted()
      try emit(
        QueryResult(
          name: name, records: total, returned: returned,
          samplesMilliseconds: samples,
          medianMilliseconds: ordered[ordered.count / 2],
          p95Milliseconds: ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1],
          loadedBodies: try await library.metrics().loadedBodies))
    }
  }

  static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
  }
  static func emit(_ value: some Encodable) throws {
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(value) + Data([10]))
  }
  private struct SeedResult: Encodable {
    let records: Int
    let target: Int
    let complete: Bool
  }
  private struct QueryResult: Encodable {
    let name: String
    let records: Int
    let returned: Int
    let samplesMilliseconds: [Double]
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let loadedBodies: Int
  }
  private enum ProbeError: Error { case usage }
}
