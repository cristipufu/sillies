import CoreML
import FluidAudio
import Foundation
import SilliesModelStore
import SilliesSpeech

/// Owns native weights off the main queue; every request owns fresh recurrent state.
actor NativeSpeechActivityEngine {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private let lease: InstalledModelLease?
  private var detector: VadManager?

  init() { lease = nil }
  init(lease: InstalledModelLease) { self.lease = lease }

  isolated deinit {
    dispatchPrecondition(condition: .notOnQueue(.main))
    detector = nil
  }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard directory.isFileURL else { throw SpeechError.invalidAudioFormat }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    let model = try MLModel(contentsOf: directory, configuration: configuration)
    try SpeechActivityModelInterface.validate(model.modelDescription)
    detector = VadManager(config: .init(computeUnits: .cpuOnly), vadModel: model)
    try Task.checkCancellation()
  }

  func containsSpeech(_ samples: [Float]) async throws -> Bool {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard samples.count <= SpeechWindowConfiguration.maximumSampleCount,
      samples.allSatisfy(\.isFinite)
    else { throw SpeechError.invalidAudioFormat }
    guard !samples.isEmpty else { return false }
    guard let detector else {
      throw SpeechError.unavailable(String(localized: "Could not prepare transcription audio."))
    }
    var state = await detector.makeStreamState()
    let threshold = await detector.currentConfig.defaultThreshold
    for start in stride(from: 0, to: samples.count, by: VadManager.chunkSize) {
      try Task.checkCancellation()
      let end = min(samples.count, start + VadManager.chunkSize)
      let result = try await detector.processStreamingChunk(
        Array(samples[start..<end]), state: state)
      try Task.checkCancellation()
      guard result.probability.isFinite, (0...1).contains(result.probability) else {
        throw SpeechError.invalidAudioFormat
      }
      if result.probability >= threshold { return true }
      state = result.state
    }
    return false
  }

}
