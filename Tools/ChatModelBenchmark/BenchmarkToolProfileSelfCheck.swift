import Foundation

/// Prevent new production tools from silently disappearing in app-profile experiments.
enum BenchmarkToolProfileSelfCheck {
  private enum Failure: Error { case omittedProductionTool, changedAblation, wrongExpansion }

  static func run() throws {
    let futureTool = "a_future_production_capability"
    for profile in [BenchmarkToolProfile.app, .expanded8, .expanded12] {
      guard profile.includes(futureTool) else { throw Failure.omittedProductionTool }
    }
    guard !BenchmarkToolProfile.none.includes("search_vault"),
      BenchmarkToolProfile.search.includes("search_vault"),
      !BenchmarkToolProfile.search.includes(futureTool),
      BenchmarkToolProfile.personal.includes("save_memory"),
      !BenchmarkToolProfile.personal.includes(futureTool)
    else { throw Failure.changedAblation }
    let expansions = [(base: 5, eight: 3, twelve: 7), (6, 2, 6), (9, 0, 3), (13, 0, 0)]
    for (count, eight, twelve) in expansions {
      guard BenchmarkToolProfile.expanded8.distractorCount(baseCount: count) == eight,
        BenchmarkToolProfile.expanded12.distractorCount(baseCount: count) == twelve,
        BenchmarkToolProfile.app.distractorCount(baseCount: count) == 0
      else { throw Failure.wrongExpansion }
    }
  }
}
