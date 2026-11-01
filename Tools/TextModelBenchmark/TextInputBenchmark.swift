import Foundation
import SilliesModelStore
import SilliesTextModels

enum TextInputBenchmark {
  static func run(registry: TextModelRegistry, manifest: TextModelManifest) async throws {
    let request = TextGenerationRequest(
      instructions: "Summarize this source.",
      prompt: String(
        repeating: "The team keeps the schedule and project notes locally. ", count: 80),
      maximumTokens: 64
    ).measuringTokens()
    let first = try await registry.complete(request, using: manifest)
    var seconds: [Double] = []
    for _ in 0..<20 {
      let start = ProcessInfo.processInfo.systemUptime
      let next = try await registry.complete(request, using: manifest)
      guard next.inputTokens == first.inputTokens else { throw TextModelError.invalidResponse }
      seconds.append(ProcessInfo.processInfo.systemUptime - start)
    }
    print(
      "TOKEN PREPARATION: tokens=\(first.inputTokens ?? -1) medianSeconds=\(seconds.sorted()[seconds.count / 2]) samples=\(seconds)"
    )
  }
}
