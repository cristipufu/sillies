import Foundation
import SilliesCore
import SilliesTextModels

/// Bounded admission only. Preparing a reply never generates a summary or walks an archive.
struct ConversationContextManager {
  enum Pressure { case normal, recovering }
  let backend: any ConversationBudgeting
  let tools: [ConversationToolDefinition]

  func prepare(_ context: ChatContext, pressure: Pressure = .normal) async throws -> ChatContext {
    let window = try ConversationRecentWindow.select(
      context, limit: backend.conversationPolicy.history.recent)
    guard let latest = window.messages.last, latest.role == .user else {
      throw TextModelError.invalidResponse
    }
    let budget = ConversationBudget(backend: backend)
    if pressure == .recovering {
      return try await minimal(window, latest: latest, capacity: budget.admissionTokens)
    }
    let measured = try await requiredTokens(window)
    if let measured,
      measured <= budget.initialTurnTokens(tools: tools)
        || (window.messages.count == 1 && measured <= budget.admissionTokens)
    {
      return window
    }
    let current = replacing(window, messages: [latest], memory: window.memory)
    let currentTokens = window.messages.count == 1 ? measured : try await requiredTokens(current)
    guard let currentTokens, currentTokens <= budget.admissionTokens else {
      if current.memory == .init(), current.background.records.isEmpty,
        current.background.personalFacts?.facts.isEmpty != false
      {
        throw TextModelError.contextLimit
      }
      return try await minimal(window, latest: latest, capacity: budget.admissionTokens)
    }
    let starts = window.messages.indices.filter { window.messages[$0].role == .user }
    var lower = min(1, starts.count - 1)
    var upper = starts.count - 1
    while lower < upper {
      try Task.checkCancellation()
      let middle = lower + (upper - lower) / 2
      let candidate = replacing(
        window, messages: Array(window.messages[starts[middle]...]), memory: window.memory)
      if try await fits(candidate, within: budget.initialTurnTokens(tools: tools)) {
        upper = middle
      } else {
        lower = middle + 1
      }
    }
    return replacing(
      window, messages: Array(window.messages[starts[lower]...]), memory: window.memory)
  }

  private func minimal(_ context: ChatContext, latest: ChatMessage, capacity: Int) async throws
    -> ChatContext
  {
    var minimal = replacing(context, messages: [latest], memory: .init())
    if try await fits(minimal, within: capacity) { return minimal }
    if !minimal.background.records.isEmpty {
      minimal = minimal.prepared(with: minimal.background.referencingRecords())
      if try await fits(minimal, within: capacity) { return minimal }
    }
    // Drop whole lowest-priority facts, never truncate a name, negation or preference mid-sentence.
    for _
      in 0..<min(
        PersonalFact.maximumPerScope * 2, minimal.background.personalFacts?.contextFacts.count ?? 0)
    {
      minimal = minimal.prepared(with: minimal.background.omittingLastFact())
      if try await fits(minimal, within: capacity) { return minimal }
    }
    throw TextModelError.contextLimit
  }

  private func fits(_ context: ChatContext, within capacity: Int) async throws -> Bool {
    try await requiredTokens(context).map { $0 <= capacity } ?? false
  }

  private func requiredTokens(_ context: ChatContext) async throws -> Int? {
    try Task.checkCancellation()
    let request = ChatReplyGenerator.request(
      for: context, tools: tools,
      maximumTokens: backend.generationProfile.conversation.outputTokens)
    let budget = ConversationBudget(backend: backend)
    guard try budget.canMeasure(request) else { return nil }
    return try await budget.requiredTokens(request)
  }

  private func replacing(
    _ context: ChatContext, messages: [ChatMessage], memory: ConversationMemory
  ) -> ChatContext {
    context.replacingHistory(messages: messages, memory: memory)
      .coveringRecentWindow()
  }
}
