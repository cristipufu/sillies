import Foundation
import MLX

/// Confined to the engine actor. Nested measurements are inclusive, never additive by default.
final class FishProfiler {
  enum Phase: String, Codable { case loading, synthesis }
  struct Chunk: Codable {
    let elapsed: TimeInterval
    let samples: Int
  }
  struct Measurement: Codable {
    var count = 0
    var totalSeconds: TimeInterval = 0
    var durations: [TimeInterval] = []
    mutating func record(_ elapsed: TimeInterval) {
      count += 1
      totalSeconds += elapsed
      if durations.count < FishProfiler.maximumStageSamples { durations.append(elapsed) }
    }
  }
  struct Report: Codable {
    let phase: Phase
    let mode: FishProfileConfiguration.Mode
    let seed: UInt64
    let elapsedSeconds: TimeInterval
    let thermalState: Int
    let activeMemoryBytes: Int
    let peakMemoryBytes: Int
    let promptTokens: Int
    let audioFrames: Int
    let stages: [String: Measurement]
    let chunks: [Chunk]
  }
  private static let maximumStageSamples = 8_192
  private let configuration: FishProfileConfiguration?
  private let now: () -> TimeInterval
  private var phase = Phase.loading
  private var started: TimeInterval = 0
  private var sequence = 0
  private var measurements: [FishProfileStage: Measurement] = [:]
  private var chunks: [Chunk] = []
  var promptTokens = 0
  var audioFrames = 0

  init(
    configuration: FishProfileConfiguration? = nil,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.configuration = configuration
    self.now = now
  }

  func begin(_ phase: Phase) {
    guard let configuration else { return }
    self.phase = phase
    measurements.removeAll(keepingCapacity: true)
    chunks.removeAll(keepingCapacity: true)
    promptTokens = 0
    audioFrames = 0
    if phase == .synthesis { MLXRandom.seed(configuration.seed) }
    started = now()
  }

  func measure<T>(_ stage: FishProfileStage, _ operation: () throws -> T) rethrows -> T {
    guard let configuration, configuration.mode != .unmeasured else { return try operation() }
    let started = now()
    defer { record(stage, elapsed: now() - started) }
    return try operation()
  }

  func tensor(_ stage: FishProfileStage, _ operation: () throws -> MLXArray) rethrows -> MLXArray {
    try measure(stage) {
      let result = try operation()
      if configuration?.mode == .fenced { eval(result) }
      return result
    }
  }

  func record(_ stage: FishProfileStage, elapsed: TimeInterval) {
    guard let configuration, configuration.mode != .unmeasured else { return }
    measurements[stage, default: Measurement()].record(elapsed)
  }

  func generated(samples: Int) {
    guard configuration != nil, chunks.count < FishConfiguration.maximumAudioFrames else { return }
    chunks.append(.init(elapsed: now() - started, samples: samples))
  }

  func report() -> Report? {
    guard let configuration else { return nil }
    return Report(
      phase: phase, mode: configuration.mode, seed: configuration.seed,
      elapsedSeconds: now() - started, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
      activeMemoryBytes: Memory.activeMemory, peakMemoryBytes: Memory.peakMemory,
      promptTokens: promptTokens, audioFrames: audioFrames,
      stages: Dictionary(uniqueKeysWithValues: measurements.map { ($0.key.rawValue, $0.value) }),
      chunks: chunks)
  }

  func finish() {
    guard let configuration, let report = report() else { return }
    let name = "\(ProcessInfo.processInfo.processIdentifier)-\(sequence)-\(phase.rawValue).json"
    sequence += 1
    do {
      try FileManager.default.createDirectory(
        at: configuration.directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(report).write(
        to: configuration.directory.appendingPathComponent(name), options: .atomic)
    } catch { fputs("Fish profiling report failed: \(error)\n", stderr) }
  }
}
