import SilliesTextModels

struct BenchmarkTextProvider: TextModelProvider {
  let base: any TextModelProvider
  let trace: BenchmarkInferenceTrace
  var id: String { base.id }
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel {
    let prepared = try await base.prepare(configuration)
    return BenchmarkTextModel(base: prepared, trace: trace)
  }
}
