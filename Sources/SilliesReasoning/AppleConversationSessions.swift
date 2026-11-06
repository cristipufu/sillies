import Foundation
import SilliesTextModels

/// One completed native session; never share mutable generation state between active turns.
actor AppleConversationSessions {
  typealias Factory =
    @Sendable (TextGenerationRequest, AppleToolInvocation) throws -> any AppleChatSession
  private struct Cached {
    let id: UUID
    let session: any AppleChatSession
    let invocation: AppleToolInvocation
    let continuation: TextConversationContinuation
  }
  private let owner = UUID()
  private let factory: Factory
  private var lifetimes: [UUID: TextModelLifetime] = [:]
  private var cached: Cached?
  private var active = false
  private var epoch = UUID()
  private var retention = TextModelRegistry.Retention.available

  init(factory: @escaping Factory = { try NativeAppleChatSession(request: $0, invocation: $1) }) {
    self.factory = factory
  }

  func retain(for lifetime: TextModelLifetime) async {
    lifetimes[lifetime.id] = lifetime
    let id = lifetime.id
    await lifetime.onEnd(owner: owner) { [weak self] in await self?.end(id) }
  }

  func stop() {
    epoch = UUID()
    cached = nil
    lifetimes.removeAll()
  }
  func setRetention(_ retention: TextModelRegistry.Retention) {
    self.retention = retention
    if retention == .memoryPressure {
      epoch = UUID()
      cached = nil
    }
  }

  func respond(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    try Task.checkCancellation()
    guard !active else { throw TextModelError.busy }
    active = true
    defer { active = false }
    let previous = cached
    cached = nil
    let generation = epoch
    let invocation: AppleToolInvocation
    let session: any AppleChatSession
    if let previous, let suffix = previous.continuation.suffix(for: request),
      suffix.count == 1, suffix.first?.role == .user, retention == .available
    {
      invocation = previous.invocation
      session = previous.session
    } else {
      invocation = AppleToolInvocation()
      session = try factory(request, invocation)
    }
    await invocation.open(tools)
    do {
      let answer = try await session.respond(request, receive: receive)
      await invocation.close()
      try Task.checkCancellation()
      // Preserve the framework-owned transcript, including native tool entries. Validate the next
      // request against our exact committed exchanges; do not reconstruct a completed native turn.
      let exchanges = await tools.exchanges
      // A clarification exits native generation through a tool error; its canonical call/result
      // is saved, but the interrupted framework transcript must not be retained for the next turn.
      let awaitsAnswer = await tools.clarification != nil
      if let id = request.sessionID, let lifetime = lifetimes[id], await lifetime.isActive,
        generation == epoch, retention == .available, !awaitsAnswer
      {
        cached = Cached(
          id: id, session: session, invocation: invocation,
          continuation: .init(
            request: request, response: .init(text: answer), completedExchanges: exchanges))
      }
      return answer
    } catch {
      await invocation.close()
      throw error
    }
  }

  private func end(_ id: UUID) {
    lifetimes[id] = nil
    if cached?.id == id { cached = nil }
  }
}
