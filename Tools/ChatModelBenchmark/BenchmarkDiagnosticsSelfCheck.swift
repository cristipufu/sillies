import Foundation
import SilliesCore
import SilliesTextModels

/// Fixture validation exercises diagnostic evidence without loading any model.
enum BenchmarkDiagnosticsSelfCheck {
  static func run() async throws {
    let generation = try reasoningRedaction()
    let original = CompanionMemory(
      replacing: nil, fact: .init(key: "name", value: "First name"),
      source: .init(messageID: UUID(), quote: "My name is First name."), savedAt: .distantPast)
    let corrected = CompanionMemory(
      replacing: original, fact: .init(key: "name", value: "Corrected name"),
      source: .init(messageID: UUID(), quote: "Please use Corrected name."), savedAt: .now)
    let trace = BenchmarkTurnTrace()
    let record = await trace.result(
      position: .init(job: "fixture", turn: 0), input: "Recall the decision",
      outcome: .failure(TextGenerationFailure(reason: .outputTokenLimit)),
      evidence: .init(
        memories: [corrected], generations: [generation],
        progress: .init(memory: .init(summary: "The verified checkpoint remains available."))))
    guard record.summary == "The verified checkpoint remains available.", record.error != nil,
      record.generations.count == 1
    else { throw Failure.lostCheckpoint }
    guard let memory = record.memories.first, memory.id == original.id,
      memory.revision == corrected.revision, memory.revision != original.revision,
      memory.sourceMessageID == corrected.sourceMessageID,
      memory.sourceMessageID != original.sourceMessageID, memory.source == corrected.sourceQuote
    else { throw Failure.lostMemoryEvidence }
  }

  private static func reasoningRedaction() throws -> BenchmarkGeneration {
    let privateState = "private-state-must-not-be-persisted"
    let call = ConversationToolCall(id: "call", name: "lookup", arguments: Data("{}".utf8))
    let request = TextGenerationRequest(
      conversation: .init(
        instructions: "Use evidence",
        messages: [.calling([call], text: "", reasoningContent: privateState)], tools: []),
      maximumTokens: 240, style: .conversation)
    let result = TextGenerationOutput(text: "A visible reply", reasoningContent: privateState)
    let generation = BenchmarkGeneration(request: request, outcome: .success(result), seconds: 1)
    let encoded = String(decoding: try JSONEncoder().encode(generation), as: UTF8.self)
    guard !encoded.contains(privateState),
      generation.inputReasoningBytes == privateState.utf8.count,
      generation.outputReasoningBytes == privateState.utf8.count,
      generation.request.messages.first?.calls == [call], generation.output?.text == result.text
    else { throw Failure.reasoningDisclosure }
    return generation
  }

  private enum Failure: Error { case lostCheckpoint, lostMemoryEvidence, reasoningDisclosure }
}
