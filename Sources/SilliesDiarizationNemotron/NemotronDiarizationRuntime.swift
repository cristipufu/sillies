import FluidAudio
import Foundation
import SilliesSpeech

/// All streams share weights and inference buffers on one serial worker.
actor NemotronDiarizationRuntime: PreparedDiarizationModel {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private static let configuration = Nemotron3Config(
    chunkLen: 32, chunkRightContext: 4, fifoLen: 40, spkcacheUpdatePeriod: 40,
    modelFileName: "Nemotron3Diarizer_s32_split_w8a8.mlmodelc", splitGraph: true)
  private static let frameDuration: TimeInterval = 0.01
  private static let validationSamples = 3 * 16_000
  private var models: Nemotron3Models?
  private var streams: [UUID: Nemotron3Diarizer] = [:]

  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func validate() async throws {
    guard let models else { throw SpeechError.unavailable("Speaker detection is not ready.") }
    try Task.checkCancellation()
    let stream = Nemotron3Diarizer(config: Self.configuration, models: models)
    stream.appendAudio([Float](repeating: 0, count: Self.validationSamples))
    let results = try stream.processBufferedAudio() + stream.finishStream()
    guard !results.isEmpty,
      results.allSatisfy({ $0.probabilities.allSatisfy { $0.isFinite && (0...1).contains($0) } })
    else {
      throw SpeechError.unavailable("The updated speaker model returned invalid predictions.")
    }
  }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    models = try await Nemotron3Models.load(
      config: Self.configuration, directory: directory, computeUnits: .cpuAndNeuralEngine)
    try Task.checkCancellation()
  }

  func makeChannel(_ request: SpeakerDiarizationRequest) async throws -> any LocalSpeechChannel {
    guard let models else { throw SpeechError.unavailable("Speaker detection is not ready.") }
    let id = UUID()
    streams[id] = Nemotron3Diarizer(config: Self.configuration, models: models)
    do {
      return try StreamingDiarizationChannel(
        engine: Stream(runtime: self, id: id), request: request)
    } catch {
      streams[id] = nil
      throw error
    }
  }

  private func process(_ samples: [Float], id: UUID) throws -> [SpeakerActivityBatch] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard let stream = streams[id] else { throw CancellationError() }
    let start = stream.streamedFrameCount
    stream.appendAudio(samples)
    return try batches(stream.processBufferedAudio(), startingAt: start)
  }

  private func finish(_ id: UUID) throws -> [SpeakerActivityBatch] {
    guard let stream = streams[id] else { return [] }
    let start = stream.streamedFrameCount
    return try batches(stream.finishStream(), startingAt: start)
  }

  private func batches(_ results: [Nemotron3ChunkResult], startingAt start: Int)
    -> [SpeakerActivityBatch]
  {
    var frame = start
    return results.map { result in
      defer { frame += result.frameCount }
      return SpeakerActivityBatch(
        start: Double(frame) * Self.frameDuration, frameDuration: Self.frameDuration,
        speakerCount: result.numSpeakers, probabilities: result.probabilities)
    }
  }

  private func remove(_ id: UUID) { streams[id] = nil }

  private final class Stream: SpeakerDiarizationEngine {
    let runtime: NemotronDiarizationRuntime
    let id: UUID
    init(runtime: NemotronDiarizationRuntime, id: UUID) {
      self.runtime = runtime
      self.id = id
    }
    deinit {
      let runtime = runtime
      let id = id
      Task { await runtime.remove(id) }
    }
    func append(_ samples: [Float]) async throws -> [SpeakerActivityBatch] {
      try await runtime.process(samples, id: id)
    }
    func finish() async throws -> [SpeakerActivityBatch] { try await runtime.finish(id) }
  }
}
