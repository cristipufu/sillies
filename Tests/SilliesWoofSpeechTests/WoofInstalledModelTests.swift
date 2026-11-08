import Foundation
import MLX
import SilliesTTS
import Testing

@testable import SilliesWoofSpeech

/// Opt-in real weights; ordinary tests never download a model or use an audio device.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SILLIES_WOOF_MODEL"] != nil))
struct WoofInstalledModelTests {
  private struct Observation: Sendable {
    let samples: [Float]
    let firstChunkSeconds: TimeInterval
    let totalSeconds: TimeInterval
  }

  init() throws { _ = try WoofRuntimeTests() }

  @Test func exhaustedFrameBudgetReportsFailureInsteadOfSuccessfulTruncation() throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_WOOF_MODEL"]))
    let arrays = try WoofTensorArchive(
      data: Data(
        contentsOf: directory.appendingPathComponent("woof_int8.npz"), options: .mappedIfSafe)
    ).arrays()
    let tree = try #require(arrays["__tree__"])
    var encoded = try #require(
      JSONSerialization.jsonObject(with: Data(tree.unicodeString().utf8)) as? [String: Any])
    encoded["max_frames"] = 4
    let configuration = try JSONDecoder().decode(
      WoofConfiguration.self, from: JSONSerialization.data(withJSONObject: encoded))
    let weights = WoofWeights(arrays: arrays)
    let voice = try weights.tensor(#require(configuration.voices["juno"]))
    let generator = try WoofLatentGenerator(configuration: configuration, weights: weights)
    var frames = 0
    #expect(throws: TTSError.self) {
      try generator.stream(
        text: "Hello! I am your little window companion.", voice: voice, seed: 0
      ) { frames += $0.dim(0) }
    }
    #expect(frames == 4)
  }

  @Test(arguments: ["cpu", "gpu"])
  func bothVoicesMatchPublishedReferenceAndRecoverFromCancellation(device: String) async throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_WOOF_MODEL"]))
    try await Device.withDefaultDevice(device == "cpu" ? .cpu : .gpu) {
      let engine = WoofSpeechEngine()
      for voice in ["juno", "mira"] {
        let observation = try await Self.synthesize(
          engine: engine, directory: directory, voice: voice)
        #expect(observation.samples.count > WoofSpeechEngine.sampleRate)
        #expect(observation.samples.contains { abs($0) > 0.01 })
        #expect(observation.samples.allSatisfy { $0.isFinite })
        try Self.compareReference(observation.samples, voice: voice)
        print(
          "Woof \(device) \(voice): first chunk \(observation.firstChunkSeconds)s, total \(observation.totalSeconds)s, samples \(observation.samples.count)"
        )
      }
      await #expect(throws: CancellationError.self) {
        try await engine.stream(
          .init(
            text: "This utterance must stop at its first delivered chunk.", voiceID: "juno",
            language: "en"),
          directory: directory, seed: 0
        ) { _ in throw CancellationError() }
      }
      let recovered = try await Self.synthesize(engine: engine, directory: directory, voice: "juno")
      try Self.compareReference(recovered.samples, voice: "juno")
    }
  }

  private static func synthesize(engine: WoofSpeechEngine, directory: URL, voice: String)
    async throws -> Observation
  {
    var samples: [Float] = []
    var firstDelivery: TimeInterval?
    let started = ProcessInfo.processInfo.systemUptime
    try await engine.stream(
      .init(text: "Hello! I am your little window companion.", voiceID: voice, language: "en"),
      directory: directory, seed: 0
    ) { chunk in
      if firstDelivery == nil { firstDelivery = ProcessInfo.processInfo.systemUptime - started }
      samples += chunk
    }
    return Observation(
      samples: samples, firstChunkSeconds: firstDelivery ?? -1,
      totalSeconds: ProcessInfo.processInfo.systemUptime - started)
  }

  private static func compareReference(_ samples: [Float], voice: String) throws {
    let url = try #require(
      Bundle.module.url(
        forResource: voice, withExtension: "f32", subdirectory: "Fixtures/Reference"))
    let data = try Data(contentsOf: url)
    try #require(!data.isEmpty && data.count.isMultiple(of: MemoryLayout<Float>.size))
    let reference = data.withUnsafeBytes { bytes in
      stride(from: 0, to: bytes.count, by: MemoryLayout<Float>.size).map {
        bytes.loadUnaligned(fromByteOffset: $0, as: Float.self)
      }
    }
    try #require(reference.count == samples.count)
    let squaredError = zip(reference, samples).reduce(0.0) { sum, pair in
      let difference = Double(pair.0 - pair.1)
      return sum + difference * difference
    }
    #expect(sqrt(squaredError / Double(samples.count)) < 0.0001)
  }
}
