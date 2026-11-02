import Foundation
import SilliesCore
import SilliesTextModels

/// Operates behind the inference gate, away from UI ownership. No fixed chat-length limit.
struct ConversationContextManager {
  enum Pressure { case normal, recovering }
  private static let toolReserveTokens = 1_536
  private static let safetyTokens = 128
  private static let maximumMeasurementBytes = 20_000
  // Keep the persistent working set below the bounded history page, independently of model size.
  private static let maximumRecentTurns = 24
  let backend: any ConversationBackend
  let tools: [ConversationToolDefinition]
  let progress: @Sendable (ChatProgress) -> Void

  private struct Reduction {
    let context: ChatContext
    let turnStarts: [Int]
    let tokenBudget: Int
  }

  func prepare(_ context: ChatContext, pressure: Pressure = .normal) async throws -> ChatContext {
    var memory = context.memory
    var pending = context.messages
    if let id = memory.throughMessageID, let index = pending.firstIndex(where: { $0.id == id }) {
      pending = Array(pending.suffix(from: index + 1))
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
        messages: pending, memory: memory
      ).inTurn(context.turnID, session: context.sessionID).inHistory(context.historyHandle)
      let request = ChatReplyGenerator.request(for: working, tools: tools)
      let requiredTokens = try await requiredTokens(for: request)
      let fits = requiredTokens.map { $0 <= budget } ?? false
      let starts = pending.indices.filter { pending[$0].role == .user }
      guard starts.count > 1 else {
        // Tool-result headroom is a compaction target, not a reason to reject the last turn.
        let admissionBudget = backend.contextWindowTokens - Self.safetyTokens
        if let requiredTokens, requiredTokens <= admissionBudget { return working }
        // Reclaim summary space before asking the user to shorten a single oversized message.
        guard
          memory.throughMessageID != nil,
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
      let next = try await retainedStart(
        for: .init(context: working, turnStarts: starts, tokenBudget: budget), pressure: pressure)
      let batch = Array(pending[..<next])
      memory = try await ConversationCompactor(backend: backend).compact(batch, into: memory)
      progress(.memory(memory))
      pending = Array(pending.suffix(from: next))
    }
  }

  /// Find the largest recent suffix that fits, then summarize its preceding complete turns once.
  /// The compactor splits oversized source batches according to the provider's actual token capacity.
  private func retainedStart(for reduction: Reduction, pressure: Pressure) async throws -> Int {
    let starts = reduction.turnStarts
    guard let currentTurn = starts.last else { throw TextModelError.contextLimit }
    if pressure == .recovering { return currentTurn }
    var lower = max(1, starts.count - Self.maximumRecentTurns)
    var upper = starts.count - 1
    while lower < upper {
      try Task.checkCancellation()
      let candidate = lower + (upper - lower) / 2
      let context = reduction.context
      let recent = ChatContext(
        companionName: context.companionName, profile: context.profile,
        messages: Array(context.messages[starts[candidate]...]), memory: context.memory
      ).inTurn(context.turnID, session: context.sessionID).inHistory(context.historyHandle)
      let request = ChatReplyGenerator.request(for: recent, tools: tools)
      if let required = try await requiredTokens(for: request), required <= reduction.tokenBudget {
        upper = candidate
      } else {
        lower = candidate + 1
      }
    }
    return starts[lower]
  }

  private func requiredTokens(for request: TextGenerationRequest) async throws -> Int? {
    let bytes =
      request.instructions.utf8.count
      + request.messages.reduce(0) {
        $0 + $1.content.utf8.count + $1.calls.reduce(0) { $0 + $1.arguments.count }
      }
    guard bytes <= Self.maximumMeasurementBytes else { return nil }
    let inputTokens = try await backend.inputTokenCount(request)
    guard inputTokens >= 0, request.maximumTokens >= 0, backend.reasoningTokenReserve >= 0 else {
      throw TextModelError.contextLimit
    }
    let generation = inputTokens.addingReportingOverflow(request.maximumTokens)
    let total = generation.partialValue.addingReportingOverflow(backend.reasoningTokenReserve)
    guard !generation.overflow, !total.overflow else { throw TextModelError.contextLimit }
    return total.partialValue
  }
}
