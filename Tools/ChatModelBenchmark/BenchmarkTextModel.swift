import SilliesTextModels

/// A diagnostic decorator; all inference and channel handling remain in the production provider.
struct BenchmarkTextModel: PreparedTextModel {
  let base: any PreparedTextModel
  let trace: BenchmarkInferenceTrace

  func generate(_ request: TextGenerationRequest) async throws -> String {
    let output = try await complete(request)
    guard output.calls.isEmpty else { throw TextModelError.invalidResponse }
    return output.text
  }
  func complete(_ request: TextGenerationRequest) async throws -> TextGenerationOutput {
    try await stream(request, receive: { _ in })
  }
  func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    guard request.operation == .generate else {
      return try await base.stream(request, receive: receive)
    }
    try BenchmarkInferenceStage.started(request)
    let started = ContinuousClock.now
    let outcome: Result<TextGenerationOutput, any Error>
    do { outcome = .success(try await base.stream(request, receive: receive)) } catch {
      outcome = .failure(error)
    }
    let generation = BenchmarkGeneration(
      request: request, outcome: outcome,
      seconds: BenchmarkTurnTrace.seconds(started.duration(to: .now)))
    try await trace.record(generation)
    try BenchmarkInferenceStage.finished(generation)
    return try outcome.get()
  }
  func stop() async { await base.stop() }
}
