import Foundation
import SilliesCore
import SilliesTextModels

/// Operates behind the inference gate, away from UI ownership. No fixed chat-length limit.
struct ConversationContextManager {
  enum Pressure { case normal, recovering }
  private static let toolReserveTokens = 1_536
  private static let safetyTokens = 128
  private static let maximumMeasurementBytes = 20_000
  private static let maximumBatchTurns = 4
  // Keep the persistent working set below the bounded history page, independently of model size.
  private static let maximumRecentTurns = 24
  let backend: any ConversationBackend
  let tools: [ConversationToolDefinition]
  let progress: @Sendable (ChatProgress) -> Void

  func prepare(_ context: ChatContext, pressure: Pressure = .normal) async throws -> ChatContext {
    var memory = context.memory
    var pending = context.messages[...]
    if let id = memory.throughMessageID, let index = pending.firstIndex(where: { $0.id == id }) {
      pending = pending.suffix(from: index + 1)
    } else {
      memory = .init(
        openingStatement: context.messages.first(where: { $0.role == .user })?.text ?? "")
    }
    let reserve =
      tools.isEmpty
      ? Self.safetyTokens : min(Self.toolReserveTokens, backend.contextWindowTokens / 3)
    let budget = backend.contextWindowTokens - reserve
    while true {
      try Task.checkCancellation()
      let working = ChatContext(
        companionName: context.companionName, profile: context.profile,
        messages: Array(pending), memory: memory
      ).inTurn(context.turnID, session: context.sessionID).inHistory(context.historyHandle)
      let request = ChatReplyGenerator.request(for: working, tools: tools)
      let fits = try await fits(request, budget: budget)
      let starts = pending.indices.filter { pending[$0].role == .user }
      guard starts.count > 1 else {
        if fits { return working }
        // Reclaim summary space before asking the user to shorten a single oversized message.
        guard
          !memory.summary.isEmpty || !memory.references.isEmpty || !memory.openingStatement.isEmpty
        else {
          throw TextModelError.contextLimit
        }
        memory = .init(
          summary: String(memory.summary.prefix(memory.summary.count / 2)),
          throughMessageID: memory.throughMessageID,
          references: Array(memory.references.dropFirst()),
          openingStatement: String(
            memory.openingStatement.prefix(memory.openingStatement.count / 2)))
        progress(.memory(memory))
        continue
      }
      if fits, pressure == .normal, starts.count <= Self.maximumRecentTurns { return working }
      progress(.compacting)
      let next = starts[min(Self.maximumBatchTurns, starts.count - 1)]
      let batch = Array(pending[..<next])
      memory = try await ConversationCompactor(backend: backend).compact(batch, into: memory)
      progress(.memory(memory))
      pending = pending.suffix(from: next)
    }
  }

  private func fits(_ request: TextGenerationRequest, budget: Int) async throws -> Bool {
    let bytes =
      request.instructions.utf8.count
      + request.messages.reduce(0) {
        $0 + $1.content.utf8.count + $1.calls.reduce(0) { $0 + $1.arguments.count }
      }
    guard bytes <= Self.maximumMeasurementBytes else { return false }
    return try await backend.inputTokenCount(request) + request.maximumTokens
      + backend.reasoningTokenReserve <= budget
  }
}
