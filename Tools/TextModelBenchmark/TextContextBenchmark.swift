import Foundation
import SilliesModelStore
import SilliesTextModels

/// Compares identical deterministic follow-ups with and without a reusable native session.
enum TextContextBenchmark {
  private static let rounds = 3
  private static let maximumTokens = 64
  private static let instructions = "Answer briefly. Follow the user's requested output format."
  private static let source =
    "The launch code is violet-42. "
    + String(repeating: "The team keeps the schedule and project notes locally. ", count: 80)
    + "Acknowledge this context by replying with exactly: Ready."

  static func run(registry: TextModelRegistry, manifest: TextModelManifest) async throws {
    for round in 0..<rounds {
      let session = UUID()
      let first = request([.init(role: .user, content: source)], session: session)
      let opening = try await registry.complete(first, using: manifest)
      print("Opening: \(String(decoding: try JSONEncoder().encode(opening.text), as: UTF8.self))")
      let messages =
        first.messages + [
          .init(role: .assistant, content: opening.text),
          .init(role: .user, content: "What is the launch code? Reply with its value only."),
        ]
      try await measure(
        "reused-\(round)", request: request(messages, session: session),
        registry: registry, manifest: manifest)
      try await measure(
        "rebuilt-\(round)", request: request(messages, session: UUID()),
        registry: registry, manifest: manifest)
    }
  }

  private static func request(_ messages: [TextMessage], session: UUID) -> TextGenerationRequest {
    TextGenerationRequest(
      conversation: .init(instructions: instructions, messages: messages, tools: []),
      maximumTokens: maximumTokens, style: .precise
    ).inSession(session).inConversation(UUID())
  }

  private static func measure(
    _ label: String, request: TextGenerationRequest,
    registry: TextModelRegistry, manifest: TextModelManifest
  ) async throws {
    let sample = ContextSample()
    let result = try await registry.stream(request, using: manifest) { _ in await sample.receive() }
    guard result.text.contains("violet-42") else { throw TextModelError.invalidResponse }
    try await sample.report(label, result: result)
  }
}

private actor ContextSample {
  private let start = ProcessInfo.processInfo.systemUptime
  private var firstDelta: Double?
  func receive() {
    if firstDelta == nil { firstDelta = ProcessInfo.processInfo.systemUptime - start }
  }
  func report(_ label: String, result: TextGenerationOutput) throws {
    struct Sample: Encodable {
      let label: String
      let firstTextSeconds: Double?
      let totalSeconds: Double
      let metrics: TextGenerationMetrics?
      let text: String
    }
    let sample = Sample(
      label: label, firstTextSeconds: firstDelta,
      totalSeconds: ProcessInfo.processInfo.systemUptime - start,
      metrics: result.metrics, text: result.text)
    print(String(decoding: try JSONEncoder().encode(sample), as: UTF8.self))
  }
}
