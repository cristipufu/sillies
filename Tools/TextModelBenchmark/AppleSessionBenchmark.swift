import Foundation
import SilliesReasoning
import SilliesTextModels

enum AppleSessionBenchmark {
  static func run() async throws {
    let backend = AppleReasoningBackend()
    if let notice = await backend.availabilityNotice(localeIdentifier: "en") {
      throw TextModelError.unavailable(notice)
    }
    let source =
      "The launch code is violet-42. "
      + String(repeating: "The team keeps the schedule and project notes locally. ", count: 60)
      + "Acknowledge with exactly Ready."
    for round in 0..<3 {
      let lifetime = TextModelLifetime()
      await backend.retain(for: lifetime)
      let messages = [TextMessage(role: .user, content: source)]
      let first = try await backend.converse(
        request(messages, session: lifetime.id), tools: toolbox())
      let history =
        messages + [
          .init(role: .assistant, content: first),
          .init(role: .user, content: "What is the launch code? Reply with its value only."),
        ]
      for (label, id) in [("reused", lifetime.id), ("rebuilt", UUID())] {
        let start = ProcessInfo.processInfo.systemUptime
        let answer = try await backend.converse(request(history, session: id), tools: toolbox())
        guard answer.contains("violet-42") else { throw TextModelError.invalidResponse }
        print(
          "APPLE CONTEXT \(round) \(label): \(ProcessInfo.processInfo.systemUptime - start)s \(answer)"
        )
      }
      await lifetime.end()
    }
    await backend.stop()
  }
  private static func toolbox() throws -> ConversationToolbox {
    try .init(tools: [], progress: { _ in })
  }
  private static func request(_ messages: [TextMessage], session: UUID) -> TextGenerationRequest {
    TextGenerationRequest(
      conversation: .init(
        instructions: "Answer briefly. Follow the user's requested output format.",
        messages: messages, tools: []), maximumTokens: 48, style: .precise
    ).inSession(session)
  }
}
