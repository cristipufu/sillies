extension TextInferenceResponse {
  /// A native tool turn may end after text delivered before its tool call. The conversation loop
  /// owns that accumulated text; transport must not mistake a verified stop for a missing response.
  func output(for request: TextGenerationRequest) throws -> TextGenerationOutput {
    if failureCode == .contextLimit { throw TextModelError.contextLimit }
    if let generationFailure { throw generationFailure }
    if let failure { throw TextModelError.unavailable(failure) }
    guard let text,
      !text.isEmpty || !(calls ?? []).isEmpty || inputTokens != nil
        || completesToolContinuation(request)
    else {
      throw TextGenerationFailure(reason: .emptyResponse, metrics: metrics)
    }
    return .init(
      text: text, calls: calls ?? [], inputTokens: inputTokens,
      metrics: metrics, reasoningContent: reasoningContent)
  }

  private func completesToolContinuation(_ request: TextGenerationRequest) -> Bool {
    // The native collector only emits completed metrics after a stop; token-limit, cancellation
    // and missing-completion failures are carried separately and rejected above.
    request.operation == .generate && request.style == .conversation
      && request.messages.last?.role == .tool && metrics != nil
  }
}
