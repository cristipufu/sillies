import Foundation
import MLXLMCommon
import SilliesTextModels

/// One native continuation, exclusively owned by MLXTextRuntime's serial generation lifecycle.
/// The SDK owns token reconciliation; the app only admits exact committed-history extensions.
actor MLXNativeConversation {
  struct Invocation: Sendable {
    let request: TextGenerationRequest
    let model: ModelContainer
    let parameters: GenerateParameters
    let components: GenerationComponents
    let templateContext: [String: any Sendable]
    var collector: MLXGenerationCollector
    let rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)?
  }

  // The SDK session has no Sendable conformance. This private handle never escapes this owner;
  // the active-operation gate and synchronization below prevent overlapping native mutations.
  private struct SessionHandle: @unchecked Sendable { let native: ChatSession }
  private struct Retained: Sendable {
    let id: UUID
    let session: SessionHandle
    let continuation: TextConversationContinuation
  }
  private struct Completion {
    let output: TextGenerationOutput
    let hasPrivateReasoning: Bool
  }
  private var retained: Retained?
  private var activeSessionID: UUID?
  private var active = false
  private var epoch = UUID()

  func release(_ id: UUID) async {
    if activeSessionID == id { epoch = UUID() }
    guard retained?.id == id else { return }
    await clear()
  }

  func clear() async {
    epoch = UUID()
    let previous = retained
    retained = nil
    await previous?.session.native.clear()
  }

  func generate(
    _ invocation: Invocation, receive: @escaping TextDeltaSink
  ) async throws -> TextGenerationOutput {
    guard !active else { throw TextModelError.busy }
    active = true
    activeSessionID = invocation.request.sessionID
    let generation = epoch
    defer {
      active = false
      activeSessionID = nil
    }
    let request = invocation.request
    let previous = retained
    retained = nil
    let session: SessionHandle
    let pending: [TextMessage]
    if let previous, let suffix = previous.continuation.suffix(for: request) {
      session = previous.session
      pending = suffix
      session.native.generateParameters = invocation.parameters
    } else {
      await previous?.session.native.clear()
      session = SessionHandle(
        native: ChatSession(
          invocation.model, instructions: request.instructions,
          generateParameters: invocation.parameters, components: invocation.components,
          additionalContext: invocation.templateContext,
          tools: MLXConversationInput.nativeTools(request)))
      pending = request.messages
    }
    let completion: Completion
    do {
      completion = try await collect(
        invocation, session: session, pending: pending, receive: receive)
      await session.native.synchronize()
      try Task.checkCancellation()
    } catch {
      await session.native.clear()
      throw error
    }
    let output = completion.output
    if let id = request.sessionID, generation == epoch, !completion.hasPrivateReasoning,
      !output.text.isEmpty || !output.calls.isEmpty
    {
      retained = Retained(
        id: id, session: session,
        continuation: .init(request: request, response: output))
    } else {
      await session.native.clear()
    }
    return output
  }

  private func collect(
    _ invocation: Invocation, session: SessionHandle, pending: [TextMessage],
    receive: @escaping TextDeltaSink
  ) async throws -> Completion {
    var collector = invocation.collector
    let messages = try MLXConversationInput.messages(pending)
    for try await event in session.native.streamDetails(to: messages) {
      try Task.checkCancellation()
      if case .rejectedToolCall(let rejection) = event {
        await invocation.rejectionObserver?(rejection)
      }
      if let delta = try collector.consume(event) { try await receive(delta) }
    }
    let output = try await collector.finish(receive: receive)
    return .init(output: output, hasPrivateReasoning: collector.hasPrivateReasoning)
  }
}
