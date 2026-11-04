import Foundation
import SilliesTextModels

/// Headless worker. A supervisor owns hard deadlines, resumable receipts, scoring and reports.
@main enum ChatModelBenchmark {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      switch arguments.count {
      case 1: try await run(load(arguments[0]))
      case 2 where arguments[0] == "--validate-fixtures":
        try await validate(load(arguments[1]))
      default: throw BenchmarkError.usage
      }
    } catch {
      fputs("Chat benchmark worker failed: \(error)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  private static func load(_ path: String) throws -> BenchmarkPlan {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(BenchmarkPlan.self, from: data)
  }

  private static func validate(_ plan: BenchmarkPlan) async throws {
    try await BenchmarkDiagnosticsSelfCheck.run()
    try BenchmarkToolProfileSelfCheck.run()
    var verified = Set<String>()
    for job in plan.jobs where verified.insert(job.scenario.id).inserted {
      let fixture = try await BenchmarkFixture.create(
        for: job.scenario, root: URL(fileURLWithPath: plan.workspace))
      fixture.remove()
    }
    print(
      "Validated \(verified.count) synthetic scenario fixtures, including screenshot retrieval.")
  }

  private static func run(_ plan: BenchmarkPlan) async throws {
    let model = try await BenchmarkModel.prepare(plan)
    let memorySearch: BenchmarkMemorySearch
    do { memorySearch = try await BenchmarkMemorySearch.prepare(plan.memorySearch) } catch {
      await model.stop()
      throw error
    }
    let lifetime = TextModelLifetime()
    await model.backend.retain(for: lifetime)
    let events = BenchmarkEvents()
    do {
      try await events.emit(.model, model.metadata)
      let runner = BenchmarkConversation(
        backend: model.backend, inference: model.inference,
        events: events, workspace: URL(fileURLWithPath: plan.workspace), memorySearch: memorySearch)
      for job in plan.jobs {
        // The supervisor admits one case at a time, so a batch can stop between cases without
        // discarding a partially evaluated conversation or unloading the model after every case.
        guard readLine() == "next" else { break }
        try await runner.run(job)
      }
      await lifetime.end()
      await memorySearch.stop()
      await model.stop()
    } catch {
      await lifetime.end()
      await memorySearch.stop()
      await model.stop()
      throw error
    }
  }
}

private enum BenchmarkError: Error {
  case usage
}
