import SilliesTextModels

/// Keep diagnostic determinism opt-in and reject ambiguous command-line seeds.
enum TextSamplingDiagnosticSelfCheck {
  private enum Failure: Error { case invalidSeedContract }

  static func run() throws {
    try checkRetentionControl()
    guard try TextInferenceInspection.samplingSeed(["helper"]) == nil,
      try TextInferenceInspection.samplingSeed(["helper", "--diagnostic-sampling-seed", "0"]) == 0,
      try TextInferenceInspection.samplingSeed([
        "helper", "--diagnostic-sampling-seed", String(UInt64.max),
      ]) == UInt64.max
    else { throw Failure.invalidSeedContract }
    for arguments in [
      ["helper", "--diagnostic-sampling-seed"],
      ["helper", "--diagnostic-sampling-seed", "-1"],
      ["helper", "--diagnostic-sampling-seed", "18446744073709551616"],
      ["helper", "--diagnostic-sampling-seed", "one"],
      ["helper", "--diagnostic-sampling-seed", "11", "--diagnostic-sampling-seed", "29"],
    ] {
      do {
        _ = try TextInferenceInspection.samplingSeed(arguments)
        throw Failure.invalidSeedContract
      } catch TextModelError.invalidResponse {}
    }
  }

  private static func checkRetentionControl() throws {
    guard try TextInferenceInspection.reproduction(["helper"]).prefixRetention == .retained,
      try TextInferenceInspection.reproduction([
        "helper", "--diagnostic-sampling-seed", "11", "--diagnostic-prefix-retention", "recomputed",
      ]).prefixRetention == .recomputed
    else { throw Failure.invalidSeedContract }
    for arguments in [
      ["helper", "--diagnostic-prefix-retention"],
      ["helper", "--diagnostic-prefix-retention", "unknown"],
      [
        "helper", "--diagnostic-prefix-retention", "retained", "--diagnostic-prefix-retention",
        "recomputed",
      ],
    ] {
      do {
        _ = try TextInferenceInspection.reproduction(arguments)
        throw Failure.invalidSeedContract
      } catch TextModelError.invalidResponse {}
    }
  }
}
