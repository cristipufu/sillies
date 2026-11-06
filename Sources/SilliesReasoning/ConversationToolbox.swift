import Foundation
import SilliesCore

/// One turn owns its tool budget and references. It cannot leak results into another conversation.
package actor ConversationToolbox {
  package static let maximumCalls = 4
  private static let maximumResultBytes = 12_000
  private static let maximumArgumentBytes = 2_048
  private static let maximumSources = 8
  package nonisolated let definitions: [ConversationToolDefinition]
  private let tools: [String: any ConversationTool]
  private let progress: @Sendable (ChatProgress) -> Void
  private var calls = 0
  private var executions = 0
  private var declinedCalls = 0
  private enum Recovery { case reducedContext, replayOnly }
  private var recovery: Recovery?
  private var cached: [String: ConversationToolOutput] = [:]

  private var resultBytes = 0
  private var evidenceBudget: ConversationEvidenceBudget?
  private var resultTokens = 0
  private var callLimit = maximumCalls
  private(set) var sources: [ChatSource] = []
  private(set) var exchanges: [ConversationToolExchange] = []
  private(set) var clarification: ChatClarification?
  var remainingCalls: Int { clarification == nil ? callLimit - calls : 0 }
  var maximumCallsForTurn: Int { callLimit }

  func configure(evidence: ConversationEvidenceBudget?, maximumCalls: Int) throws {
    guard maximumCalls > 0, resultTokens == 0 else { throw ToolFailure.budget }
    evidenceBudget = evidence
    callLimit = maximumCalls
  }

  func includeSelectedSources(_ sources: [ChatSource]) { publish(sources) }

  package init(tools: [any ConversationTool], progress: @escaping @Sendable (ChatProgress) -> Void)
    throws
  {
    definitions = tools.map(\.definition)
    guard Set(definitions.map(\.name)).count == tools.count else { throw ToolFailure.duplicate }
    self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.definition.name, $0) })
    self.progress = progress
  }

  func beginRecovery() throws {
    try begin(.reducedContext)
  }

  func beginReplay() throws {
    try begin(.replayOnly)
  }

  private func begin(_ mode: Recovery) throws {
    guard recovery == nil else { throw ToolFailure.budget }
    recovery = mode
    calls = 0
    declinedCalls = 0
    resultBytes = 0
    resultTokens = 0
  }

  package func invoke(_ call: ConversationToolCall) async throws -> String {
    try Task.checkCancellation()
    if clarification != nil {
      return try await decline(call, reason: .awaitingUserAnswer)
    }
    guard let tool = tools[call.name] else { throw ToolFailure.unknown }
    guard call.arguments.count <= Self.maximumArgumentBytes else { throw ToolFailure.budget }
    let key = try cacheKey(for: call)
    guard calls < callLimit else { return try await decline(call) }
    calls += 1
    // Recovery can replay cached evidence, but cannot acquire a second execution allowance.
    if cached[key] == nil {
      guard recovery != .replayOnly else {
        return try await decline(call, reason: .recoveryReplayOnly)
      }
      guard executions < callLimit else { return try await decline(call) }
      executions += 1
    }
    progress(.usingTool(tool.activity))
    defer { progress(.generating) }
    let result: ConversationToolOutput
    do {
      result = try await load(call, using: tool, key: key)
    } catch let error as ConversationToolArguments.Failure {
      return try await recordOutput(
        .init(text: error.response(for: tool.definition, remainingCalls: remainingCalls)), for: call
      )
    }
    // A committed memory must remain visible even if cancellation arrives after its write.
    if let receipt = result.memoryReceipt { progress(.remembered(receipt)) }
    try Task.checkCancellation()
    if let question = result.clarification {
      guard clarification == nil else {
        return try await decline(call, reason: .awaitingUserAnswer)
      }
      clarification = question
    }
    publish(result.sources)
    do { return try await recordOutput(result, for: call) } catch {
      if let question = result.clarification, clarification?.id == question.id {
        clarification = nil
      }
      throw error
    }
  }

  private func recordOutput(_ output: ConversationToolOutput, for call: ConversationToolCall)
    async throws -> String
  {
    let text: String
    if let evidenceBudget {
      let selected = try await evidenceBudget.select(
        output, remaining: evidenceBudget.totalTokens - resultTokens)
      resultTokens += selected.tokens
      text = selected.text
    } else {
      text = recovery == .reducedContext ? output.briefText : output.text
    }
    return try recordExchange(text, for: call)
  }

  private func decline(
    _ call: ConversationToolCall, reason: ToolNotExecutedResult.Reason = .turnToolLimitReached
  ) async throws -> String {
    guard declinedCalls < callLimit else { throw ToolFailure.budget }
    declinedCalls += 1
    let text = String(
      decoding: try JSONEncoder().encode(ToolNotExecutedResult(reason: reason)), as: UTF8.self)
    return try await recordOutput(.init(text: text), for: call)
  }

  private func recordExchange(_ text: String, for call: ConversationToolCall) throws -> String {
    guard text.utf8.count <= Self.maximumResultBytes - resultBytes else {
      throw ToolFailure.budget
    }
    resultBytes += text.utf8.count
    exchanges.append(.init(call: call, result: text))
    return text
  }

  private func cacheKey(for call: ConversationToolCall) throws -> String {
    guard let object = try JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]
    else {
      throw ToolFailure.arguments
    }
    return call.name
      + String(
        decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
        as: UTF8.self)
  }

  private func load(_ call: ConversationToolCall, using tool: any ConversationTool, key: String)
    async throws -> ConversationToolOutput
  {
    let result: ConversationToolOutput
    if let previous = cached[key] {
      result = previous
    } else {
      result = try await tool.call(arguments: call.arguments)
      cached[key] = result
    }
    return result
  }

  private func publish(_ discovered: [ChatSource]) {
    for source in discovered {
      if let index = sources.firstIndex(where: { $0.id == source.id }) {
        sources[index] = source
      } else if sources.count < Self.maximumSources {
        sources.append(source)
      }
    }
    progress(.sources(sources))
  }
}

private enum ToolFailure: LocalizedError {
  case duplicate, unknown, budget, arguments
  var errorDescription: String? {
    switch self {
    case .arguments:
      String(
        localized: "The local text model returned an incomplete response. Your source is unchanged."
      )
    case .duplicate: String(localized: "Duplicate conversation tool registration.")
    case .unknown:
      String(localized: "The model requested an unavailable tool. Your Vault is unchanged.")
    case .budget:
      String(
        localized:
          "This search reached its limit. Narrow your question; the results found so far are kept.")
    }
  }
}
