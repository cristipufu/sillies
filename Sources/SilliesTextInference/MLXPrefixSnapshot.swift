import Foundation
import MLX
import MLXLMCommon
import SilliesTextModels

/// Native caches never escape ModelContainer.perform. MLXTextRuntime admits one operation at a
/// time and drains generation before release. This capsule only bridges that SDK isolation.
final class MLXPrefixSnapshot: @unchecked Sendable {
  /// Recomputed is a diagnostic control: preserve token boundaries, never the native arrays.
  enum Retention: String, Sendable { case retained, recomputed }
  struct Status: Codable, Sendable {
    let tokens: Int
    let bytes: Int
  }
  struct Prepared {
    let cache: [KVCache]
    let state: LMOutput.State?
    let consumedTokens: Int
    let reusedTokens: Int
    let preparationSeconds: Double
  }
  struct Capture {
    let sessionID: UUID
    let tokens: [Int]
    let cache: [KVCache]
    let state: LMOutput.State?
  }
  private struct Entry {
    let sessionID: UUID
    let tokens: [Int]
    let cache: [KVCache]
    let bytes: Int
  }
  private var entry: Entry?
  private let retention: Retention
  init(retention: Retention = .retained) { self.retention = retention }
  var status: Status { .init(tokens: entry?.tokens.count ?? 0, bytes: entry?.bytes ?? 0) }

  func matches(tokens: [Int], sessionID: UUID?) -> Bool {
    guard let entry else { return false }
    return entry.sessionID == sessionID && tokens.count > entry.tokens.count
      && tokens.starts(with: entry.tokens)
  }

  func clear() { entry = nil }
  func release(_ sessionID: UUID) {
    if entry?.sessionID == sessionID { clear() }
  }

  func capture(_ snapshot: Capture, limits: TextModelPreparation.RuntimePolicy.PrefixSnapshot) {
    clear()
    guard limits.isValid, snapshot.state == nil, !snapshot.tokens.isEmpty,
      snapshot.tokens.count <= limits.maximumTokens
    else { return }
    var bytes = 0
    for array in snapshot.cache.flatMap(\.state) {
      guard array.nbytes <= limits.maximumBytes - bytes else { return }
      bytes += array.nbytes
    }
    entry = Entry(
      sessionID: snapshot.sessionID, tokens: snapshot.tokens,
      cache: retention == .retained ? snapshot.cache.map { $0.copy() } : [],
      bytes: retention == .retained ? bytes : 0)
  }

  func restore(tokens: [Int], sessionID: UUID?) -> Prepared? {
    guard retention == .retained, matches(tokens: tokens, sessionID: sessionID), let entry else {
      return nil
    }
    return .init(
      cache: entry.cache.map { $0.copy() }, state: nil,
      consumedTokens: entry.tokens.count, reusedTokens: entry.tokens.count, preparationSeconds: 0)
  }

  func prepare(
    tokens: [Int], boundary: Int, plan: MLXGenerationPlan, context: ModelContext
  ) throws -> Prepared {
    let started = ContinuousClock.now
    if let restored = restore(tokens: tokens, sessionID: plan.request.generation.sessionID) {
      return restored
    }
    let previousBoundary =
      matches(tokens: tokens, sessionID: plan.request.generation.sessionID)
      ? entry?.tokens.count : nil
    clear()
    let cache = try context.model.newCache(parameters: plan.parameters)
    guard let policy = plan.request.configuration.profile.runtimePolicy.prefixSnapshot,
      let sessionID = plan.request.generation.sessionID
    else { throw TextModelError.invalidResponse }
    let count = min(previousBoundary ?? boundary, policy.maximumTokens, max(0, tokens.count - 1))
    guard count > 0 else {
      return .init(
        cache: cache, state: nil, consumedTokens: 0, reusedTokens: 0, preparationSeconds: 0)
    }
    let prefix = Array(tokens.prefix(count))
    let output = try Self.prefill(prefix, into: cache, plan: plan, context: context)
    eval(cache)
    try Task.checkCancellation()
    let elapsed = started.duration(to: .now).components
    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    // The public State type can carry arbitrary objects and has no size/copy contract. Preserve
    // it for this generation, but never retain it. Recurrent KV caches have native copy semantics.
    capture(
      .init(sessionID: sessionID, tokens: prefix, cache: cache, state: output.state), limits: policy
    )
    return .init(
      cache: cache, state: output.state, consumedTokens: count, reusedTokens: 0,
      preparationSeconds: seconds)
  }

  static func prefill(
    _ tokens: [Int], into cache: [KVCache], plan: MLXGenerationPlan, context: ModelContext
  ) throws -> LMOutput {
    let input = LMInput(tokens: MLXArray(tokens))
    switch try context.model.prepare(
      input, cache: cache, state: nil, prefill: plan.parameters.prefill)
    {
    case .tokens(let remaining):
      return context.model(remaining[text: .newAxis], cache: cache, state: nil)
    case .logits(let prepared): return prepared
    }
  }
}
