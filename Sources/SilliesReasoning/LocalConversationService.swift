import SilliesCore
import SilliesTextModels

package actor LocalConversationService: ConversationResponding {
  private let backend: @Sendable () async -> any ReasoningBackend
  private let tools: [any ConversationTool]
  private let turns: ReasoningTurnGate
  private let history: ConversationHistoryAccess
  private let maintenance: ConversationCheckpointMaintenance?

  package init(
    resolveBackend: @escaping @Sendable () async -> any ReasoningBackend,
    tools: [any ConversationTool], turns: ReasoningTurnGate,
    history: ConversationHistoryAccess = .transient
  ) {
    backend = resolveBackend
    self.tools = tools
    self.turns = turns
    self.history = history
    maintenance = history.repository.map {
      ConversationCheckpointMaintenance(
        repository: $0, resolveBackend: resolveBackend, turns: turns)
    }
  }
  package func availabilityNotice(localeIdentifier: String?) async -> String? {
    await backend().availabilityNotice(localeIdentifier: localeIdentifier)
  }
  package func retain(for lifetime: TextModelLifetime) async {
    await maintenance?.retain(for: lifetime)
    let selected = await backend()
    await (selected as? any ConversationBackend)?.retain(for: lifetime)
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
    do {
      let reply = try await respond(
        to: context, backend: selected, progress: progress, receive: receive)
      await turns.release()
      await maintenance?.enqueue(context)
      return reply
    } catch {
      await turns.release()
      await maintenance?.enqueue(context)
      throw error
    }
  }

  private func respond(
    to context: ChatContext, backend selected: any ConversationBackend,
    progress: @escaping @Sendable (ChatProgress) -> Void, receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    try Task.checkCancellation()
    let toolbox = try ConversationToolbox(tools: tools + history.tools(context), progress: progress)
    let manager = ConversationContextManager(backend: selected, tools: toolbox.definitions)
    let source: ChatContext
    if let repository = history.repository, context.historyHandle != nil {
      source = try await ConversationHistoryPreparation(
        repository: repository, limit: selected.conversationPolicy.history.recent
      ).prepare(context)
    } else {
      source = context
    }
    var working = try await manager.prepare(source)
    let text: String
    let delivery = ConversationStreamDelivery(receive: receive)
    do {
      text = try await ChatReplyGenerator.reply(
        to: working, backend: selected, tools: toolbox, receive: delivery.append)
    } catch TextModelError.contextLimit {
      guard await !delivery.hasOutput else { throw TextModelError.contextLimit }
      // A backend can include hidden framing or a tool result that changes the budget.
      // Retry once; tool results (including writes) are cached for this turn.
      try await toolbox.beginRecovery()
      working = try await manager.prepare(working, pressure: .recovering)
      text = try await ChatReplyGenerator.reply(
        to: working, backend: selected, tools: toolbox, receive: delivery.append)
    }
    try Task.checkCancellation()
    return await ChatReply(
      text: text, sources: toolbox.sources, exchanges: toolbox.exchanges, memory: source.memory)
  }

}
