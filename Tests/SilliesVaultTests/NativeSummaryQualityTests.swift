import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning

/// These outputs require semantic review against the printed sources, not keyword-only scoring.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_SUMMARY_QUALITY_CHECK"] == "1"))
func nativeCheckpointSummaryProvenance() async throws {
  let model = try await NativeConversationModel.prepare()
  do {
    for sample in SummaryQualitySample.all {
      let started = ContinuousClock.now
      let output = try await ConversationCompactor(backend: model.backend).compact(
        sample.messages, into: sample.memory)
      let result = try #require(output)
      #expect(result.throughMessageID == sample.messages.last?.id)
      print(
        "SUMMARY SOURCE \(sample.id): \(String(decoding: try JSONEncoder().encode(sample.messages), as: UTF8.self))"
      )
      print(
        "SUMMARY OUTPUT \(model.id) \(sample.id): \(String(decoding: try JSONEncoder().encode(result), as: UTF8.self)); elapsed=\(started.duration(to: .now))"
      )
    }
    await model.stop()
  } catch {
    await model.stop()
    throw error
  }
}

private struct SummaryQualitySample {
  let id: String
  let messages: [ChatMessage]
  var memory = ConversationMemory()

  static var all: [Self] {
    [
      .init(
        id: "no-facts",
        messages: (0..<24).map {
          .init(role: $0.isMultiple(of: 2) ? .user : .companion, text: "Archived discussion \($0).")
        }),
      .init(
        id: "no-facts-with-opening",
        messages: (0..<24).map {
          .init(role: $0.isMultiple(of: 2) ? .user : .companion, text: "Archived discussion \($0).")
        }, memory: .init(openingStatement: "Archived discussion 0.")),
      .init(
        id: "identity-correction",
        messages: [
          .init(role: .user, text: "My name is Alex."),
          .init(role: .companion, text: "I'm Alex, your window companion."),
          .init(role: .user, text: "No, your name is Pogo. I am Alex."),
          .init(role: .companion, text: "Understood."),
        ]),
      .init(
        id: "deadline-correction",
        messages: [
          .init(role: .user, text: "The launch deadline changed from May 9 to May 11."),
          .init(role: .companion, text: "I will keep May 9 in mind."),
          .init(role: .user, text: "No, May 11 is the current deadline."),
          .init(role: .companion, text: "Understood."),
        ], memory: .init(summary: "The launch deadline is May 9.", throughMessageID: UUID())),
      .init(
        id: "hypothetical",
        messages: [
          .init(
            role: .user,
            text: "If I moved to Oslo, what would winter be like? This is hypothetical."),
          .init(role: .companion, text: "Winters in Oslo can be cold and snowy."),
        ]),
      .init(
        id: "assistant-policy-is-not-user-fact",
        messages: [
          .init(role: .user, text: "My name is Alex, and I prefer jasmine tea."),
          .init(role: .companion, text: "Nice to meet you, Alex."),
          .init(role: .user, text: "What is my name?"),
          .init(
            role: .companion,
            text: "I cannot disclose your name because I must respect your privacy."),
        ],
        memory: .init(
          summary: "The assistant refuses to discuss the user's personal information.",
          throughMessageID: UUID())),
    ]
  }
}
