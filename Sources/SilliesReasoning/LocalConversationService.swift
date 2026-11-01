import SilliesCore
import SilliesTextModels

package actor LocalConversationService: ConversationResponding {
  private let backend: @Sendable () async -> any ReasoningBackend
  private let tools: [any ConversationTool]
  private let turns: ReasoningTurnGate

  package init(
    resolveBackend: @escaping @Sendable () async -> any ReasoningBackend,
    tools: [any ConversationTool], turns: ReasoningTurnGate
  ) {
    backend = resolveBackend
    self.tools = tools
    self.turns = turns
  }
  package func availabilityNotice(localeIdentifier: String?) async -> String? {
    await backend().availabilityNotice(localeIdentifier: localeIdentifier)
  }
  package func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    try await streamReply(to: context, progress: progress, receive: { _ in })
  }
  package func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    guard context.messages.last?.role == .user else { throw TextModelError.invalidResponse }
    let selected = await backend()
    if let notice = await selected.availabilityNotice(
      localeIdentifier: context.profile.languageIdentifier)
    {
      throw TextModelError.unavailable(notice)
    }
    guard let selected = selected as? any ConversationBackend else {
      throw TextModelError.toolsUnavailable
    }
    try await turns.acquire(.interactive)
    defer { Task { await turns.release() } }
    try Task.checkCancellation()
    let toolbox = try ConversationToolbox(tools: tools, progress: progress)
    let manager = ConversationContextManager(
      backend: selected, tools: toolbox.definitions, progress: progress)
    var working = try await manager.prepare(context)
    let text: String
    let delivery = ConversationStreamDelivery(receive: receive)
    do {
      text = try await ChatReplyGenerator.reply(
        to: working, backend: selected, tools: toolbox, receive: delivery.append)
    } catch TextModelError.contextLimit {
      guard await !delivery.hasOutput else { throw TextModelError.contextLimit }
      // A backend can include hidden framing or a tool result that changes the budget.
      // Retry once; all operations are read-only and already discovered cards remain available.
      try await toolbox.beginRecovery()
      working = try await manager.prepare(
        contextWithMemory(context, working.memory), pressure: .recovering)
      text = try await ChatReplyGenerator.reply(
        to: working, backend: selected, tools: toolbox, receive: delivery.append)
    }
    try Task.checkCancellation()
    return await ChatReply(
      text: text, sources: toolbox.sources, exchanges: toolbox.exchanges, memory: working.memory)
  }

  private func contextWithMemory(_ context: ChatContext, _ memory: ConversationMemory)
    -> ChatContext
  {
    .init(
      companionName: context.companionName, profile: context.profile, messages: context.messages,
      memory: memory, turnID: context.turnID)
  }
}
