import Foundation
import SilliesTextModels

/// Headless worker. A supervisor owns hard deadlines, resumable receipts, scoring and reports.
@main enum ChatModelBenchmark {
  static func main() async {
    do {
      guard CommandLine.arguments.count == 2 else {
        throw BenchmarkError.usage
      }
      let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
      let plan = try JSONDecoder().decode(BenchmarkPlan.self, from: data)
      try await run(plan)
    } catch {
      fputs("Chat benchmark worker failed: \(error)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  private static func run(_ plan: BenchmarkPlan) async throws {
    let model = try await BenchmarkModel.prepare(plan)
    let lifetime = TextModelLifetime()
    await model.backend.retain(for: lifetime)
    let events = BenchmarkEvents()
    do {
      try await events.emit(.model, model.metadata)
      let runner = BenchmarkConversation(
        backend: model.backend, events: events, workspace: URL(fileURLWithPath: plan.workspace))
      for job in plan.jobs {
        // The supervisor admits one case at a time, so a batch can stop between cases without
        // discarding a partially evaluated conversation or unloading the model after every case.
        guard readLine() == "next" else { break }
        try await runner.run(job)
      }
      await lifetime.end()
      await model.stop()
    } catch {
      await lifetime.end()
      await model.stop()
      throw error
    }
  }
}

private enum BenchmarkError: Error {
  case usage
}
