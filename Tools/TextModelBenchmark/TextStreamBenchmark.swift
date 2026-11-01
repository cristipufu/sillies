import Foundation
import SilliesModelStore
import SilliesTextModels

/// Opt-in timing of real deltas; a whole-result adapter cannot pass this streaming check.
enum TextStreamBenchmark {
  static func run(registry: TextModelRegistry, manifest: TextModelManifest) async throws {
    let samples = TextStreamSamples()
    let request = TextGenerationRequest(
      instructions:
        "You are Bolt, a friendly fictional window companion. Use plain text and keep replies brief.",
      prompt: "Introduce yourself in two short sentences.", maximumTokens: 240, style: .conversation
    ).inConversation(UUID())
    let result = try await registry.stream(request, using: manifest) { delta in
      await samples.append(delta)
    }
    try await samples.report(final: result.text)
  }
}

private actor TextStreamSamples {
  private let started = ContinuousClock.now
  private var firstDelta: Duration?
  private var count = 0
  private var text = ""
  func append(_ delta: String) {
    if firstDelta == nil { firstDelta = started.duration(to: .now) }
    count += 1
    text += delta
  }
  func report(final: String) throws {
    guard count > 1, let firstDelta, text.trimmingCharacters(in: .whitespacesAndNewlines) == final
    else {
      throw TextModelError.invalidResponse
    }
    print(
      "Streaming text: \(count) deltas; first text \(firstDelta); total \(started.duration(to: .now)); reply: \(final)"
    )
  }
}
