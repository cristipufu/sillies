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
  private var declinedCalls = 0
  private var recovering = false
  private var cached: [String: ConversationToolOutput] = [:]

  private var resultBytes = 0
  private(set) var sources: [ChatSource] = []
  private(set) var exchanges: [ConversationToolExchange] = []
  var remainingCalls: Int { Self.maximumCalls - calls }

  package init(tools: [any ConversationTool], progress: @escaping @Sendable (ChatProgress) -> Void)
    throws
  {
    definitions = tools.map(\.definition)
    guard Set(definitions.map(\.name)).count == tools.count else { throw ToolFailure.duplicate }
    self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.definition.name, $0) })
    self.progress = progress
  }

  func beginRecovery() throws {
    guard !recovering else { throw ToolFailure.budget }
    recovering = true
    calls = 0
    declinedCalls = 0
    resultBytes = 0
  }

  package func invoke(_ call: ConversationToolCall) async throws -> String {
    try Task.checkCancellation()
    guard let tool = tools[call.name] else { throw ToolFailure.unknown }
    guard call.arguments.count <= Self.maximumArgumentBytes else { throw ToolFailure.budget }
    let key = try cacheKey(for: call)
    guard calls < Self.maximumCalls else { return try decline(call) }
    calls += 1
    progress(.usingTool(tool.activity))
    let result = try await load(call, using: tool, key: key)
    // A committed memory must remain visible even if cancellation arrives after its write.
    if let receipt = result.memoryReceipt { progress(.remembered(receipt)) }
    try Task.checkCancellation()
    publish(result.sources)
    let text = recovering ? result.briefText : result.text
    return try recordExchange(text, for: call)
  }

  private func decline(_ call: ConversationToolCall) throws -> String {
    // Native tool loops also receive an explicit stop result, with a bounded refusal allowance.
    guard declinedCalls < Self.maximumCalls else { throw ToolFailure.budget }
    declinedCalls += 1
    let text = String(decoding: try JSONEncoder().encode(ToolLimitResult()), as: UTF8.self)
    return try recordExchange(text, for: call)
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

private struct ToolLimitResult: Encodable {
  let status = "notExecuted"
  let reason = "turnToolLimitReached"
  let remainingCalls = 0
  let coverage =
    "No operation was performed. The tool allowance for this turn is exhausted. Answer from the results already returned and state any missing evidence; do not request more tools."
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
