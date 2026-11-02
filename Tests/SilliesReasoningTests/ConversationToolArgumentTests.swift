import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning

private actor ArgumentReadProbe: ConversationTool {
  enum Behavior { case read, corruptStorage, cancelled }
  private struct Arguments: Decodable {
    let recordID: UUID
    let query: String
  }
  nonisolated let definition = ConversationToolDefinition(
    name: "read", description: "Read a saved record",
    parameters: [.init("recordID", description: "A UUID"), .init("query", description: "Topic")])
  nonisolated let activity = "Reading"
  private let behavior: Behavior
  private(set) var storageReads = 0

  init(_ behavior: Behavior = .read) { self.behavior = behavior }

  func call(arguments: Data) throws -> ConversationToolOutput {
    let request = try ConversationToolArguments.decode(Arguments.self, from: arguments)
    storageReads += 1
    switch behavior {
    case .read: return .init(text: request.query)
    case .corruptStorage:
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Corrupt store"))
    case .cancelled: throw CancellationError()
    }
  }
}

private let validReadArguments = Data(
  #"{"recordID":"00000000-0000-0000-0000-000000000001","query":"checklist"}"#.utf8)

@Test(arguments: [
  (#"{"recordID":"00000000-0000-0000-0000-000000000001"}"#, "query"),
  (#"{"recordID":"not-a-record-id","query":"checklist"}"#, "recordID"),
])
func invalidToolArgumentsReturnCorrectableEvidenceBeforeAnyStorageAccess(
  arguments: String, parameter: String
) async throws {
  let tool = ArgumentReadProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let invalid = ConversationToolCall(id: "invalid", name: "read", arguments: Data(arguments.utf8))
  let result = try await toolbox.invoke(invalid)
  let value = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
  #expect(value["status"] as? String == "notExecuted")
  #expect(value["reason"] as? String == "invalidArguments")
  #expect(value["parameter"] as? String == parameter)
  #expect(value["remainingCalls"] as? Int == ConversationToolbox.maximumCalls - 1)
  #expect(await tool.storageReads == 0)
  #expect(await toolbox.exchanges.last?.call.id == invalid.id)

  let corrected = ConversationToolCall(id: "corrected", name: "read", arguments: validReadArguments)
  #expect(try await toolbox.invoke(corrected) == "checklist")
  #expect(await tool.storageReads == 1)
  #expect(await toolbox.exchanges.map(\.call.id) == ["invalid", "corrected"])
}

@Test func argumentCorrectionAttemptsConsumeTheExistingToolBudget() async throws {
  let tool = ArgumentReadProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  for index in 0..<ConversationToolbox.maximumCalls {
    _ = try await toolbox.invoke(.init(id: "\(index)", name: "read", arguments: Data("{}".utf8)))
  }
  let result = try await toolbox.invoke(
    .init(id: "after-budget", name: "read", arguments: validReadArguments))
  #expect(result.contains("turnToolLimitReached"))
  #expect(await tool.storageReads == 0)
}

@Test func argumentRecoveryNeverMislabelsCorruptStorageAsBadModelArguments() async throws {
  let tool = ArgumentReadProbe(.corruptStorage)
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  await #expect(throws: DecodingError.self) {
    try await toolbox.invoke(.init(id: "read", name: "read", arguments: validReadArguments))
  }
  #expect(await tool.storageReads == 1)
  #expect(await toolbox.exchanges.isEmpty)
}

@Test func argumentRecoveryPreservesCancellation() async throws {
  let tool = ArgumentReadProbe(.cancelled)
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  await #expect(throws: CancellationError.self) {
    try await toolbox.invoke(.init(id: "read", name: "read", arguments: validReadArguments))
  }
  #expect(await toolbox.exchanges.isEmpty)
}
