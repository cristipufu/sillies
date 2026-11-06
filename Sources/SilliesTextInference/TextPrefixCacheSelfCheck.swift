import Foundation
import MLX
import MLXLMCommon
import SilliesTextModels

/// Tests snapshot ownership with native arrays; no downloaded weights, UI or clock budgets.
enum TextPrefixCacheSelfCheck {
  static func run() throws {
    try checkSamplingContext()
    try checkSnapshotOwnership()
  }

  private static func checkSamplingContext() throws {
    let constraints = try CheckpointGenerationConstraints.validated(tokens: [1], vocabularySize: 3)
    let parameters = GenerateParameters(
      temperature: 0, repetitionPenalty: 2, repetitionContextSize: 4)
    guard let base = constraints.components.logitProcessor(parameters: parameters) else {
      throw TextModelError.invalidResponse
    }
    var processor = MLXCompletePromptProcessor(base: base, tokens: [0, 2])
    // Token zero is in the cached prefix, absent from the live suffix, and must stay penalized.
    processor.prompt(MLXArray([2]))
    let output = processor.process(logits: MLXArray([Float(8), 100, 6]).reshaped(1, 3))
    guard output.asArray(Float.self) == [4, -Float.infinity, 3] else {
      throw TextModelError.invalidResponse
    }
  }

  private static func checkSnapshotOwnership() throws {
    let session = UUID()
    let tokens = [1, 2, 3]
    let cache = KVCacheSimple()
    let key = MLXArray.ones([1, 1, tokens.count, 4])
    _ = cache.update(keys: key, values: key)
    eval(cache)
    let snapshot = MLXPrefixSnapshot()
    let capture = MLXPrefixSnapshot.Capture(
      sessionID: session, tokens: tokens, cache: [cache], state: nil)
    let limits = TextModelPreparation.RuntimePolicy.PrefixSnapshot(
      maximumTokens: 8, maximumBytes: 1_024)
    snapshot.capture(capture, limits: limits)
    let continuation = tokens + [4]
    let recomputed = MLXPrefixSnapshot(retention: .recomputed)
    recomputed.capture(capture, limits: limits)
    guard recomputed.matches(tokens: continuation, sessionID: session),
      recomputed.restore(tokens: continuation, sessionID: session) == nil,
      recomputed.status.tokens == tokens.count, recomputed.status.bytes == 0
    else { throw TextModelError.invalidResponse }
    guard snapshot.matches(tokens: continuation, sessionID: session),
      !snapshot.matches(tokens: tokens, sessionID: session),
      !snapshot.matches(tokens: continuation, sessionID: UUID()),
      !snapshot.matches(tokens: [1, 9, 3, 4], sessionID: session),
      !snapshot.matches(tokens: continuation, sessionID: nil),
      let first = snapshot.restore(tokens: continuation, sessionID: session)
    else { throw TextModelError.invalidResponse }
    _ = first.cache[0].update(keys: key, values: key)
    eval(first.cache)
    guard let second = snapshot.restore(tokens: continuation, sessionID: session),
      second.cache[0].offset == tokens.count, first.cache[0].offset == tokens.count * 2
    else { throw TextModelError.invalidResponse }
    snapshot.release(UUID())
    guard snapshot.status.tokens == tokens.count else { throw TextModelError.invalidResponse }
    snapshot.release(session)
    guard snapshot.status.tokens == 0, snapshot.status.bytes == 0 else {
      throw TextModelError.invalidResponse
    }
    let context = TextGenerationRequest.ContextIdentity(history: UUID(), personalFacts: UUID())
    var revised = capture
    revised.contextIdentity = context
    snapshot.capture(revised, limits: limits)
    guard snapshot.matches(tokens: continuation, sessionID: session, contextIdentity: context),
      snapshot.restore(
        tokens: continuation, sessionID: session,
        contextIdentity: .init(history: UUID(), personalFacts: context.personalFacts)) == nil,
      snapshot.restore(
        tokens: continuation, sessionID: session,
        contextIdentity: .init(history: context.history, personalFacts: UUID())) == nil
    else { throw TextModelError.invalidResponse }
    snapshot.capture(capture, limits: .init(maximumTokens: 8, maximumBytes: 1))
    guard snapshot.status.tokens == 0 else { throw TextModelError.invalidResponse }
    snapshot.capture(capture, limits: .init(maximumTokens: 1, maximumBytes: 1_024))
    guard snapshot.status.tokens == 0 else { throw TextModelError.invalidResponse }
    snapshot.capture(
      .init(sessionID: session, tokens: tokens, cache: [cache], state: LMOutput.State()),
      limits: limits)
    guard snapshot.status.tokens == 0 else { throw TextModelError.invalidResponse }
  }
}
