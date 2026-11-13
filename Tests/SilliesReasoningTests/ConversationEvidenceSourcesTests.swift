import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning

@Test func toolEvidencePublishesOnlyTheAdmittedRepresentation() async throws {
  let source = evidenceSource()
  let brief = source.withExcerpt("Saved")
  let output = ConversationToolOutput(
    text: String(repeating: "x", count: 500), sources: [source], briefText: "Short result"
  )
  .withEvidence([.init(text: "Short result", sources: [brief])])
  let toolbox = try ConversationToolbox(
    tools: [EvidenceOutputTool(output: output)], progress: { _ in })
  try await toolbox.configure(
    evidence: .init(totalTokens: 100, resultTokens: 100, measure: { $0.count }), maximumCalls: 4)
  let result = try await toolbox.invoke(.init(id: "1", name: "read", arguments: Data("{}".utf8)))
  #expect(result == "Short result")
  #expect(await toolbox.sources == [brief])
}

@Test func omittedAndRejectedToolResultsSupplyNoSourceEvidence() async throws {
  let output = ConversationToolOutput(
    text: String(repeating: "x", count: 12_001), sources: [evidenceSource()])
  let toolbox = try ConversationToolbox(
    tools: [EvidenceOutputTool(output: output)], progress: { _ in })
  try await toolbox.configure(
    evidence: .init(
      totalTokens: 10, resultTokens: 10,
      measure: {
        $0.contains("outputOmitted") ? 1 : 100
      }), maximumCalls: 4)
  let result = try await toolbox.invoke(.init(id: "1", name: "read", arguments: Data("{}".utf8)))
  #expect(result.contains("outputOmitted"))
  #expect(await toolbox.sources.isEmpty)
  let rejected = try ConversationToolbox(
    tools: [EvidenceOutputTool(output: output)], progress: { _ in })
  await #expect(throws: (any Error).self) {
    try await rejected.invoke(.init(id: "2", name: "read", arguments: Data("{}".utf8)))
  }
  #expect(await rejected.sources.isEmpty)
}

@Test func recoveryReplacesTheEarlierAttemptWithItsAdmittedEvidence() async throws {
  let source = evidenceSource()
  let brief = source.withExcerpt("Saved")
  let output = ConversationToolOutput(text: "Full result", sources: [source], briefText: "Brief")
    .withEvidence([.init(text: "Brief", sources: [brief])])
  let toolbox = try ConversationToolbox(
    tools: [EvidenceOutputTool(output: output)], progress: { _ in })
  _ = try await toolbox.invoke(.init(id: "first", name: "read", arguments: Data("{}".utf8)))
  #expect(await toolbox.sources == [source])
  try await toolbox.beginRecovery()
  #expect(await toolbox.sources.isEmpty)
  _ = try await toolbox.invoke(.init(id: "retry", name: "read", arguments: Data("{}".utf8)))
  #expect(await toolbox.sources == [brief])
}

private struct EvidenceOutputTool: ConversationTool {
  let output: ConversationToolOutput
  var definition: ConversationToolDefinition {
    .init(name: "read", description: "Read evidence", parameters: [])
  }
  var activity: String { "Reading" }
  func call(arguments: Data) -> ConversationToolOutput { output }
}

private func evidenceSource() -> ChatSource {
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")))
  return .init(header: .init(record), excerpt: "Saved evidence that exceeds the brief version.")
}
